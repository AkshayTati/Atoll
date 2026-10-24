#ifndef ISLET_MEDIA_REMOTE_SHIM_H
#define ISLET_MEDIA_REMOTE_SHIM_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// True when MediaRemote.framework loaded and the required symbols resolved.
bool islet_mr_available(void);

/// Fetch the current now-playing dictionary. The callback runs on a
/// background queue with a NULL dictionary when nothing is playing.
void islet_mr_request_now_playing(void (*callback)(CFDictionaryRef info, void *context),
                                  void *context);

/// Send a MediaRemote command:
/// 0 = play, 1 = pause, 2 = toggle play/pause, 3 = stop, 4 = next, 5 = previous.
void islet_mr_send_command(int command);

#ifdef __cplusplus
}
#endif

#endif
