//
//  NativeCounters.h
//  SwiftCore
//
//  Created by vsmbd on 25/01/26.
//

#ifndef EVENTDISPATCH_NATIVE_COUNTERS_H
#define EVENTDISPATCH_NATIVE_COUNTERS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Returns a monotonically increasing event id (starting from 1).
/// Thread-safe on supported platforms/toolchains.
uint64_t nextEventID(void);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // EVENTDISPATCH_NATIVE_COUNTERS_H
