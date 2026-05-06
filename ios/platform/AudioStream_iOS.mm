// SPDX-FileCopyrightText: 2002-2025 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+
// iOS implementation of AudioStream using AVAudioEngine
// MUST be .mm (Objective-C++) — non-negotiable (uses AVFoundation)

#if ! __has_feature(objc_arc)
    #error "Compile this with -fobjc-arc"
#endif

#include "Host/AudioStream.h"
#include "Host/AudioStreamTypes.h"
#include "Console.h"

#include <AVFoundation/AVFoundation.h>
#include <AudioToolbox/AudioToolbox.h>

// MARK: - AudioStream_iOS

@interface BionicSX2AudioDelegate : NSObject <AVAudioPlayerDelegate>
{
    PCSX2::Host::AudioStream* _stream;
}
- (instancetype)initWithStream:(PCSX2::Host::AudioStream*)stream;
@end

@implementation BionicSX2AudioDelegate
- (instancetype)initWithStream:(PCSX2::Host::AudioStream*)stream
{
    self = [super init];
    if (self)
        _stream = stream;
    return self;
}
@end

namespace PCSX2::Host
{

class AudioStream_iOS final : public AudioStream
{
public:
    AudioStream_iOS(u32 sample_rate, u32 channels, u32 bits)
        : AudioStream(sample_rate, channels, bits)
        , m_engine(nullptr)
        , m_player(nullptr)
    {}

    ~AudioStream_iOS() override
    {
        Shutdown();
    }

    bool OpenDevice() override
    {
        // Configure AVAudioSession (mandatory on iOS)
        AVAudioSession* session = [AVAudioSession sharedInstance];
        NSError* error = nil;

        // Set category to Playback (mute switch doesn't affect)
        if (![session setCategory:AVAudioSessionCategoryPlayback error:&error])
        {
            Console.Error("Failed to set audio session category: {}",
                [[error localizedDescription] UTF8String]);
            return false;
        }

        // Activate the audio session
        if (![session setActive:true error:&error])
        {
            Console.Error("Failed to activate audio session: {}",
                [[error localizedDescription] UTF8String]);
            return false;
        }

        // Create AVAudioEngine
        m_engine = [[AVAudioEngine alloc] init];
        if (!m_engine)
        {
            Console.Error("Failed to create AVAudioEngine.");
            return false;
        }

        // Configure for our audio format
        AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:m_sample_rate
                                                                 channels:m_channels];
        if (!format)
        {
            Console.Error("Failed to create audio format (rate={}, channels={})",
                m_sample_rate, m_channels);
            m_engine = nil;
            return false;
        }

        // Prepare the engine
        if (![m_engine prepare:nil])
        {
            Console.Error("Failed to prepare AVAudioEngine.");
            m_engine = nil;
            return false;
        }

        m_is_open = true;
        return true;
    }

    void CloseDevice() override
    {
        if (m_engine)
        {
            [m_engine stop:nil];
            m_engine = nil;
        }

        // Deactivate audio session
        NSError* error = nil;
        [[AVAudioSession sharedInstance] setActive:false error:&error];

        m_is_open = false;
    }

    bool Start() override
    {
        if (!m_engine)
            return false;

        NSError* error = nil;
        if (![m_engine startAndReturnError:&error])
        {
            Console.Error("Failed to start AVAudioEngine: {}",
                [[error localizedDescription] UTF8String]);
            return false;
        }

        m_is_running = true;
        return true;
    }

    void Stop() override
    {
        if (m_engine)
            [m_engine pause];
        m_is_running = false;
    }

    u32 GetBufferedFrames() const override
    {
        // AVAudioEngine doesn't expose buffered frame count directly
        // Return 0 to indicate "not applicable"
        return 0;
    }

    u32 GetAvailableFrames() const override
    {
        // For AVAudioEngine, we don't have a direct query
        // Return a reasonable estimate
        return m_sample_rate / 10; // ~100ms of buffer
    }

    void FramesAvailable() override
    {
        // Called when new frames are available to play
        // AVAudioEngine handles this internally via its render block
    }

    void SetPaused(bool paused) override
    {
        if (!m_engine)
            return;

        if (paused)
            [m_engine pause];
        else
            [m_engine startAndReturnError:nil];
    }

    float GetOutputVolume() const override
    {
        if (!m_engine)
            return 0.0f;
        return [m_engine outputVolume];
    }

    void SetOutputVolume(float volume) override
    {
        if (m_engine)
            [m_engine setOutputVolume:volume];
    }

    void pWriteFramesOnBuffer(const void* frames, u32 count) override
    {
        // AVAudioEngine uses a render block, not direct buffer writing
        // This function should not be called in the AVAudioEngine implementation
        Console.Warning("pWriteFramesOnBuffer called on AVAudioEngine stream — not supported.");
    }

private:
    AVAudioEngine* m_engine;
    BionicSX2AudioDelegate* m_delegate;
};

AudioStream* AudioStream::Create(u32 sample_rate, u32 channels, u32 bits)
{
    return new AudioStream_iOS(sample_rate, channels, bits);
}

} // namespace PCSX2::Host
