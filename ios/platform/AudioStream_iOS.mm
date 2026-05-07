// SPDX-FileCopyrightText: 2002-2025 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+
// iOS implementation of AudioStream using AVAudioEngine + AVAudioSourceNode
// MUST be .mm (Objective-C++) — non-negotiable (uses AVFoundation)

#if ! __has_feature(objc_arc)
    #error "Compile this with -fobjc-arc"
#endif

#include "Host/AudioStream.h"
#include "Host/AudioStreamTypes.h"
#include "common/Console.h"
#include "common/Error.h"

#include <AVFoundation/AVFoundation.h>
#include <AudioToolbox/AudioToolbox.h>
#include <cstring>

// MARK: - AudioStream_iOS

namespace PCSX2::Host
{

class AudioStream_iOS final : public AudioStream
{
public:
    AudioStream_iOS(u32 sample_rate, const AudioStreamParameters& parameters, bool stretch_enabled)
        : AudioStream(sample_rate, parameters)
        , m_engine(nullptr)
        , m_source_node(nullptr)
        , m_audio_format(nil)
    {
        BaseInitialize(SampleReaderImpl<AudioExpansionMode::Disabled>, stretch_enabled);
    }

    ~AudioStream_iOS() override
    {
        CloseDevice();
    }

    bool OpenDevice() override
    {
        NSError* error = nil;

        // Configure AVAudioSession (mandatory on iOS)
        AVAudioSession* session = [AVAudioSession sharedInstance];

        // Set category to Playback (mute switch doesn't affect)
        if (![session setCategory:AVAudioSessionCategoryPlayback error:&error])
        {
            Console.Error("Failed to set audio session category: {}",
                [[error localizedDescription] UTF8String]);
            return false;
        }

        // Set preferred sample rate
        [session setPreferredSampleRate:m_sample_rate error:nil];

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

        // Create audio format: signed 16-bit interleaved -> we'll convert to float in the render block
        // AVAudioSourceNode expects non-interleaved float format
        AudioStreamBasicDescription hwFormat;
        memset(&hwFormat, 0, sizeof(hwFormat));
        hwFormat.mSampleRate = m_sample_rate;
        hwFormat.mFormatID = kAudioFormatLinearPCM;
        hwFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved;
        hwFormat.mBytesPerPacket = sizeof(float);
        hwFormat.mFramesPerPacket = 1;
        hwFormat.mBytesPerFrame = sizeof(float);
        hwFormat.mChannelsPerFrame = m_internal_channels;
        hwFormat.mBitsPerChannel = 32;

        m_audio_format = [[AVAudioFormat alloc] initWithStreamDescription:&hwFormat];
        if (!m_audio_format)
        {
            Console.Error("Failed to create audio format (rate={}, channels={})",
                m_sample_rate, m_internal_channels);
            m_engine = nil;
            return false;
        }

        // Create source node with render block.
        // this is captured by value (pointer copy). The block is owned by m_source_node,
        // which is detached in CloseDevice() before the AudioStream_iOS is destroyed.
        // Stopping the engine and detaching the node ensures the block is not called
        // after teardown.
        AudioStream_iOS* capturedSelf = this;
        m_source_node = [[AVAudioSourceNode alloc] initWithRenderBlock:
            ^OSStatus(BOOL* isSilence, const AudioTimeStamp* timestamp,
                      AVAudioFrameCount frameCount, AudioBufferList* outputData)
            {
                return capturedSelf->RenderAudio(outputData, frameCount, isSilence);
            }];

        if (!m_source_node)
        {
            Console.Error("Failed to create AVAudioSourceNode.");
            m_engine = nil;
            return false;
        }

        // Attach source node to engine
        [m_engine attachNode:m_source_node];

        // Connect source node to main mixer
        [m_engine connect:m_source_node to:[m_engine mainMixerNode] format:m_audio_format];

        m_is_open = true;
        return true;
    }

    void CloseDevice() override
    {
        if (m_engine)
        {
            // Stop engine first to prevent further render block calls
            [m_engine stop];

            // Detach source node to release the block (and its capture of this)
            if (m_source_node)
            {
                [m_engine detachNode:m_source_node];
                m_source_node = nil;
            }

            m_engine = nil;
        }

        m_audio_format = nil;

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
        return GetBufferedFramesRelaxed();
    }

    u32 GetAvailableFrames() const override
    {
        // Return how many frames we can still write
        return m_buffer_size - GetBufferedFramesRelaxed();
    }

    void FramesAvailable() override
    {
        // AVAudioSourceNode pull-based — the render block is called when the audio system
        // needs data, so we don't need to notify it explicitly.
        // This method is called when new frames are written to the buffer.
    }

    void SetPaused(bool paused) override
    {
        if (!m_engine)
            return;

        if (paused)
            [m_engine pause];
        else
            [m_engine startAndReturnError:nil];

        m_paused = paused;
    }

    float GetOutputVolume() const override
    {
        if (!m_engine)
            return 0.0f;
        return m_engine.mainMixerNode.volume;
    }

    void SetOutputVolume(float volume) override
    {
        if (m_engine)
            m_engine.mainMixerNode.volume = volume;
        m_volume = volume;
    }

private:
    OSStatus RenderAudio(AudioBufferList* outputData, AVAudioFrameCount frameCount, BOOL* isSilence)
    {
        // Calculate how many frames are available
        const u32 available = GetBufferedFramesRelaxed();
        const u32 frames_to_read = std::min(static_cast<u32>(frameCount), available);

        if (frames_to_read == 0)
        {
            // No data available — output silence
            *isSilence = YES;
            for (UInt32 i = 0; i < outputData->mNumberBuffers; i++)
            {
                memset(outputData->mBuffers[i].mData, 0, outputData->mBuffers[i].mDataByteSize);
            }
            return noErr;
        }

        // Read frames from the ring buffer
        // We need a temporary buffer for interleaved s16 data
        const u32 num_samples = frames_to_read * m_internal_channels;
        std::unique_ptr<s16[]> temp_buffer = std::make_unique<s16[]>(num_samples);
        ReadFrames(temp_buffer.get(), frames_to_read);

        // Convert s16 to float and write to output buffers (non-interleaved)
        // temp_buffer is interleaved: L0,R0,L1,R1,... for stereo
        for (UInt32 i = 0; i < outputData->mNumberBuffers && i < m_internal_channels; i++)
        {
            float* dest = static_cast<float*>(outputData->mBuffers[i].mData);
            for (UInt32 frame = 0; frame < frames_to_read; frame++)
            {
                // Deinterleave: channel i is at index (frame * channels + i)
                s16 sample = temp_buffer[frame * m_internal_channels + i];
                dest[frame] = sample / 32768.0f;
            }
        }

        *isSilence = NO;
        return noErr;
    }

    AVAudioEngine* m_engine;
    AVAudioSourceNode* m_source_node;
    AVAudioFormat* m_audio_format;
};

std::unique_ptr<AudioStream> CreateIOSAudioStream(u32 sample_rate, const AudioStreamParameters& parameters,
    bool stretch_enabled, Error* error)
{
    auto stream = std::make_unique<AudioStream_iOS>(sample_rate, parameters, stretch_enabled);
    if (!stream->OpenDevice())
    {
        Error::SetStringView(error, "Failed to open iOS audio device.");
        return nullptr;
    }
    return stream;
}

} // namespace PCSX2::Host
