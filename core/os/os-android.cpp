#include <QCoreApplication>
#include <QJniObject>
#include <QJniEnvironment>
#include <QDebug>
#include <QScopeGuard>
#include <QUrl>

#include "os.h"

// The Android context (the activity, if there is one).
// Qt 6.2 returns a jobject, newer versions a QJniObject. Both work here.
static QJniObject androidContext()
{
    return QJniObject(QNativeInterface::QAndroidApplication::context());
}

static bool is_content_url(const char *path)
{
    const char pattern[] = "content:";
    return strncmp(pattern, path, sizeof(pattern) - 1) == 0;
}

// A handler to open android content:// URLs.
// Based on code by Florin9doi: https://github.com/nspire-emus/firebird/pull/94/files
FILE *fopen_utf8(const char *path, const char *mode)
{
    if(!is_content_url(path))
        return fopen(path, mode);

    QString android_mode; // Why did they have to NIH...
    if(strcmp(mode, "rb") == 0)
        android_mode = QStringLiteral("r");
    else if(strcmp(mode, "r+b") == 0)
        android_mode = QStringLiteral("rw");
    else if(strcmp(mode, "wb") == 0)
        android_mode = QStringLiteral("rwt");
    else
        return nullptr;

    QJniObject jpath = QJniObject::fromString(QString::fromUtf8(path));
    QJniObject jmode = QJniObject::fromString(android_mode);
    QJniObject uri = QJniObject::callStaticObjectMethod(
                "android/net/Uri", "parse", "(Ljava/lang/String;)Landroid/net/Uri;",
                jpath.object<jstring>());

    QJniObject contentResolver = androidContext()
            .callObjectMethod("getContentResolver",
                              "()Landroid/content/ContentResolver;");

    // Call contentResolver.takePersistableUriPermission as we save the URI
    int permflags = 1; // Intent.FLAG_GRANT_READ_URI_PERMISSION
    if(android_mode.contains(QLatin1Char('w')))
        permflags |= 2; // Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    contentResolver.callMethod<void>("takePersistableUriPermission",
                                     "(Landroid/net/Uri;I)V", uri.object<jobject>(), permflags);

    QJniEnvironment env;

    if (env->ExceptionCheck())
    {
        env->ExceptionDescribe();
        env->ExceptionClear();
    }

    QJniObject parcelFileDescriptor = contentResolver
            .callObjectMethod("openFileDescriptor",
                              "(Landroid/net/Uri;Ljava/lang/String;)Landroid/os/ParcelFileDescriptor;",
                              uri.object<jobject>(), jmode.object<jobject>());

    if (env->ExceptionCheck())
    {
        env->ExceptionDescribe();
        env->ExceptionClear();
        return nullptr;
    }

    // The file descriptor needs to be duplicated as
    QJniObject parcelFileDescriptorDup = parcelFileDescriptor
            .callObjectMethod("dup",
                              "()Landroid/os/ParcelFileDescriptor;");

    if (env->ExceptionCheck())
    {
        env->ExceptionDescribe();
        env->ExceptionClear();
        return nullptr;
    }

    int fd = parcelFileDescriptorDup.callMethod<jint>("detachFd", "()I");
    if(fd < 0)
        return nullptr;

    return fdopen(fd, mode);
}

static QString android_basename_using_content_resolver(const QString &path)
{
    QJniObject jpath = QJniObject::fromString(path);
    QJniObject uri = QJniObject::callStaticObjectMethod(
                "android/net/Uri", "parse", "(Ljava/lang/String;)Landroid/net/Uri;",
                jpath.object<jstring>());

    QJniObject contentResolver = androidContext()
            .callObjectMethod("getContentResolver",
                              "()Landroid/content/ContentResolver;");

    QJniEnvironment env;
    QJniObject col = QJniObject::getStaticObjectField("android/provider/OpenableColumns", "DISPLAY_NAME", "Ljava/lang/String;");
    QJniObject proj = env->NewObjectArray(1, env->FindClass("java/lang/String"), col.object<jstring>());

    QJniObject cursor = contentResolver.callObjectMethod("query", "(Landroid/net/Uri;[Ljava/lang/String;Landroid/os/Bundle;Landroid/os/CancellationSignal;)Landroid/database/Cursor;", uri.object<jobject>(), proj.object<jobject>(),
                                                         static_cast<jobject>(nullptr), static_cast<jobject>(nullptr));
    if (env->ExceptionCheck())
    {
        env->ExceptionDescribe();
        env->ExceptionClear();
        return {};
    }

    if(!cursor.isValid())
        return {};

    auto closeCursor = qScopeGuard([&] { cursor.callMethod<void>("close", "()V"); });

    bool hasContent = cursor.callMethod<jboolean>("moveToFirst", "()Z");
    if (env->ExceptionCheck())
    {
        env->ExceptionDescribe();
        env->ExceptionClear();
        return {};
    }

    if(!hasContent)
        return {};

    QJniObject name = cursor.callObjectMethod("getString", "(I)Ljava/lang/String;", 0);
    if (!name.isValid())
        return {};

    return name.toString();
}

char *android_basename(const char *path)
{
    if (is_content_url(path))
    {
        // Example: content://com.android.externalstorage.documents/document/primary%3AFirebird%2Fflash_tpad
        QString pathStr = QString::fromUtf8(path);
        QString ret = android_basename_using_content_resolver(pathStr);
        // If that failed (e.g. because the permission expired), try to get something recognizable.
        if (ret.isEmpty())
        {
            qWarning() << "Failed to get basename of" << pathStr << "using ContentResolver";
            const auto parts = pathStr.split(QStringLiteral("%2F"), Qt::SkipEmptyParts, Qt::CaseInsensitive);
            if(parts.length() > 1)
                ret = QUrl::fromPercentEncoding(parts.last().toUtf8());
        }

        if (!ret.isEmpty())
            return strdup(ret.toUtf8().data());
    }

    return nullptr;
}

void androidVibrate()
{
    // The window is only available if the context is an activity.
    if(!QNativeInterface::QAndroidApplication::isActivityContext())
        return;

    QJniEnvironment env;

    // Call activity.getWindow().getDecorView().performHapticFeedback(KEYBOARD_TAP);
    QJniObject window = androidContext()
            .callObjectMethod("getWindow", "()Landroid/view/Window;");

    QJniObject decorView = window.callObjectMethod("getDecorView", "()Landroid/view/View;");

    if (env->ExceptionCheck())
    {
        env->ExceptionDescribe();
        env->ExceptionClear();
        return;
    }

    bool success = decorView.callMethod<jboolean>("performHapticFeedback", "(I)Z", 3); // HapticFeedbackConstants.KEYBOARD_TAP

    if (env->ExceptionCheck())
    {
        env->ExceptionDescribe();
        env->ExceptionClear();
        return;
    }

    if (!success)
        qInfo() << "Haptic feedback failed";
}
