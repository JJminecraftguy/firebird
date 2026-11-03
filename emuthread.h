#ifndef EMUTHREAD_H
#define EMUTHREAD_H

#ifdef __EMSCRIPTEN__
#include <QTimer>
#else
#include <QThread>
#endif

#ifdef __EMSCRIPTEN__
class EmuThread : public QTimer
#else
class EmuThread : public QThread
#endif
{
    Q_OBJECT
public:
    explicit EmuThread(QObject *parent = 0);

    void doStuff(bool wait);
    void throttleTimerWait(unsigned int usec);

    QString boot1, flash;
    unsigned int port_gdb = 0, port_rdbg = 0;

#ifdef __EMSCRIPTEN__
    bool isRunning() { return isActive(); }
#endif

signals:
    // State
    void started(bool success); // Not called on resume
    void resumed(bool success);
    void suspended(bool success);
    void stopped();
    void paused(bool b);

    // I/O
    void serialChar(char c);

    // Status
    void isBusy(bool busy);
    void statusMsg(QString str);
    void speedChanged(double value);
    void usblinkChanged(bool state);
    void turboModeChanged(bool state);

    // Debugging
    void debugStr(QString str);
    void debuggerEntered(bool state);
    void debugInputRequested(bool b);

public slots:
#ifdef __EMSCRIPTEN__
    void start();
#else
    virtual void run() override;
#endif

    // State
    void setPaused(bool is_paused);
    bool stop();
    void reset();
    bool resume(QString path);
    void suspend(QString path);

    // Emulation settings
    void setTurboMode(bool state);
    void toggleTurbo();

    // Debugging
    void enterDebugger();
    void debuggerInput(QString str);

#ifdef __EMSCRIPTEN__
    void loopStep();
#endif

private:
    bool enter_debugger = false;
    bool is_paused = false, do_suspend = false, do_resume = false;
    std::string debug_input, snapshot_path;

#ifdef __EMSCRIPTEN__
    void startup(bool reset);
#endif
};

extern EmuThread emu_thread;

#endif // EMUTHREAD_H
