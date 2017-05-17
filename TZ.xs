#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <time.h>
#include <string.h>


#define TIME_STRING_SIZE 26


/* thanks to Michael Schout's Env::C module, this solves problem with FreeBSD */

/* in order to work around system and perl implementation bugs/leaks, we need
 * to sometimes force PERL_USE_SAFE_PUTENV mode.
 */
#ifndef PERL_USE_SAFE_PUTENV
   /* Threaded perl with PERL_TRACK_MEMPOOL enabled causes
    * "panic: free from wrong pool at exit"
    * starting at 5.9.4 (confirmed through 5.20.1)
    * see: https://rt.cpan.org/Ticket/Display.html?id=99962
    */
# if PERL_BCDVERSION >= 0x5009004 && defined(USE_ITHREADS) && defined(PERL_TRACK_MEMPOOL)
#  define USE_SAFE_PUTENV 1
# elif PERL_BCDVERSION >= 0x5008000 && PERL_BCDVERSION < 0x5019006
   /* FreeBSD: SIGV at exit on perls prior to 5.19.6
    * see: https://rt.cpan.org/Ticket/Display.html?id=49872
    */
#  if defined(__FreeBSD__)
#   define USE_SAFE_PUTENV 1
#  endif
# endif
#endif



#if defined(WIN32)
void inline setenv(const char *name, const char *value, const int flag) {
    _putenv_s(name, value);
}

void inline unsetenv(const char *name) {
    _putenv_s(name, "");
}

void inline localtime_r(const time_t *time, struct tm *tm) {
    localtime_s(tm, time);
}

void inline asctime_r(const struct tm *tm, char* time_string) {
    asctime_s(time_string, TIME_STRING_SIZE, tm);
}

void inline gmtime_r(const time_t *time, struct tm *tm) {
    gmtime_s(tm, time);
}

#endif

#define BACKUP_TZ()                                           \
    char* old_tz_p = getenv("TZ");                            \
    int envsize = old_tz_p == NULL ? 1 : strlen(old_tz_p)+1;  \
    char old_tz[envsize];                                     \
    if (old_tz_p != NULL)                                     \
        memcpy(old_tz, old_tz_p, envsize);                    \

#define RESTORE_TZ()                                          \
    if (old_tz_p == NULL) {                                   \
        unsetenv("TZ");                                       \
    } else {                                                  \
        setenv("TZ", old_tz, 1);                              \
    }                                                         \


MODULE = Time::Local::TZ		PACKAGE = Time::Local::TZ
PROTOTYPES: DISABLE

BOOT:
# ifdef USE_SAFE_PUTENV
PL_use_safe_putenv = 1;
# endif


void
tz_localtime(tz, time)
    char* tz
    time_t time
    PREINIT:
        char time_string[TIME_STRING_SIZE];
        struct tm tm;
    PPCODE:
        BACKUP_TZ();
            setenv("TZ", tz, 1);
            tzset();
            localtime_r(&time, &tm);
        RESTORE_TZ();

        if (GIMME_V == G_ARRAY) {
            EXTEND(SP, 9);
            ST(0) = sv_2mortal(newSViv(tm.tm_sec));
            ST(1) = sv_2mortal(newSViv(tm.tm_min));
            ST(2) = sv_2mortal(newSViv(tm.tm_hour));
            ST(3) = sv_2mortal(newSViv(tm.tm_mday));
            ST(4) = sv_2mortal(newSViv(tm.tm_mon));
            ST(5) = sv_2mortal(newSViv(tm.tm_year));
            ST(6) = sv_2mortal(newSViv(tm.tm_wday));
            ST(7) = sv_2mortal(newSViv(tm.tm_yday));
            ST(8) = sv_2mortal(newSViv(tm.tm_isdst));
            XSRETURN(9); 
        } else {
#ifdef sun
            asctime_r(&tm, time_string, TIME_STRING_SIZE);
#else
            asctime_r(&tm, time_string);
#endif
            ST(0) = sv_2mortal(newSVpv(time_string, 24));
            XSRETURN(1);
        }


void
tz_timelocal(...)
    PREINIT:
        char* tz;
        struct tm tm;
        time_t time;
    PPCODE:
        if (items < 7 || items > 10)
            croak("Usage: tz_timelocal(tz, sec, min, hour, mday, mon, year, [ wday, yday, is_dst ])");

        tz = SvPV_nolen(ST(0));
        tm.tm_sec   = SvIV(ST(1));
        tm.tm_min   = SvIV(ST(2));
        tm.tm_hour  = SvIV(ST(3));
        tm.tm_mday  = SvIV(ST(4));
        tm.tm_mon   = SvIV(ST(5));
        tm.tm_year  = SvIV(ST(6));
        tm.tm_wday  = -1;
        tm.tm_yday  = -1;
        tm.tm_isdst = -1;

        BACKUP_TZ();
            setenv("TZ", tz, 1);
            tzset();
            time = mktime(&tm);
        RESTORE_TZ();

        ST(0) = sv_2mortal(newSViv((IV)time));
        XSRETURN(1);


void
tz_truncate(tz, time, unit)
    char* tz
    time_t time
    int unit
    PREINIT:
        struct tm tm;
    PPCODE:
        if (unit < 1 || unit > 5)
            croak("Usage: tz_truncate(tz, time, unit), unit should be 1..5");

        BACKUP_TZ();
            setenv("TZ", tz, 1);
            tzset();
            localtime_r(&time, &tm);
            if (unit == 5) tm.tm_mon  = 0;
            if (unit >= 4) tm.tm_mday = 1;
            if (unit >= 3) tm.tm_hour = 0;
            if (unit >= 2) tm.tm_min  = 0;
            if (unit >= 1) tm.tm_sec  = 0;
            time = mktime(&tm);
        RESTORE_TZ();

        ST(0) = sv_2mortal(newSViv((IV)time));
        XSRETURN(1);


void
tz_offset(tz, time)
    char* tz
    time_t time
    PREINIT:
        struct tm tm;
        time_t time_utc;
    PPCODE:
        BACKUP_TZ()
            setenv("TZ", tz, 1);
            tzset();
            gmtime_r(&time, &tm);
            time_utc = mktime(&tm);
        RESTORE_TZ();

        ST(0) = sv_2mortal(newSViv((int)(time-time_utc)));
        XSRETURN(1);
