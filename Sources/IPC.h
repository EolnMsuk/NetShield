#pragma once
#import <Foundation/Foundation.h>

// Private to the IPC worker; never exempt ordinary app loopback traffic.
enum { NSIPCPort = 49671, NSIPCMaxPayload = 8192, NSIPCTimeoutMilliseconds = 250 };
NSDictionary *NSRequestPolicy(NSDictionary *info);
// Register once on the main thread. The handler also runs on the main queue.
BOOL NSStartIPCServer(NSDictionary *(^handler)(NSDictionary *));
