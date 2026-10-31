#import <Onyx2D/O2DataConsumer.h>
#import <Onyx2D/O2Image.h>
#import <stdbool.h>
#import <stdint.h>

typedef struct O2PNGEncoder {
    O2DataConsumerRef _consumer;
    bool _complete;
    bool _failed;
} * O2PNGEncoderRef;

O2PNGEncoderRef O2PNGEncoderCreate(O2DataConsumerRef consumer);
void O2PNGEncoderDealloc(O2PNGEncoderRef self);

void O2PNGEncoderWriteImage(O2PNGEncoderRef self, O2ImageRef image, CFDictionaryRef properties);

bool O2PNGEncoderIsComplete(O2PNGEncoderRef self);
