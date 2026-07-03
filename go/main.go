package main

/*
#cgo darwin LDFLAGS: -framework CoreAudio -framework AudioUnit -framework AudioToolbox -framework CoreFoundation
#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AudioToolbox.h>

// Unified signature to basic void* pointers to align completely with Cgo export mappings
OSStatus goAudioRenderCallback(
    void *inRefCon,
    void *ioActionFlags,
    void *inTimeStamp,
    UInt32 inBusNumber,
    UInt32 inNumberFrames,
    void *ioData);

static OSStatus initCoreAudio(AudioUnit *outUnit) {
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_DefaultOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;

    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (comp == NULL) return kAudioUnitErr_NoConnection;

    OSStatus status = AudioComponentInstanceNew(comp, outUnit);
    if (status != noErr) return status;

    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = (AURenderCallback)goAudioRenderCallback;
    callbackStruct.inputProcRefCon = NULL;

    status = AudioUnitSetProperty(*outUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  0, 
                                  &callbackStruct,
                                  sizeof(callbackStruct));
    if (status != noErr) return status;

    AudioStreamBasicDescription streamFormat;
    streamFormat.mSampleRate       = 44100.0;
    streamFormat.mFormatID         = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    streamFormat.mBitsPerChannel   = 32;
    streamFormat.mChannelsPerFrame = 2;
    streamFormat.mFramesPerPacket  = 1;
    streamFormat.mBytesPerFrame    = 4;
    streamFormat.mBytesPerPacket   = 4;

    status = AudioUnitSetProperty(*outUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &streamFormat,
                                  sizeof(streamFormat));
    if (status != noErr) return status;

    return AudioUnitInitialize(*outUnit);
}
*/
import "C"

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
	"unsafe"
)

const tracksStatePath = "/tmp/daw-tracks-v2.txt"

type Track struct {
	Volume float32
	Muted  bool
}

var (
	gTracks = [2]Track{
		{Volume: 1.0, Muted: false},
		{Volume: 1.0, Muted: true},
	}
	gEngineMutex sync.Mutex
)

//export goAudioRenderCallback
func goAudioRenderCallback(
	inRefCon unsafe.Pointer,
	ioActionFlags unsafe.Pointer,
	inTimeStamp unsafe.Pointer,
	inBusNumber C.UInt32,
	inNumberFrames C.UInt32,
	ioData unsafe.Pointer,
) C.OSStatus {
	
	if ioData == nil {
		return C.noErr
	}

	frameCount := int(inNumberFrames)
	
	gEngineMutex.Lock()
	trackVolume := gTracks[0].Volume
	trackMuted := gTracks[0].Muted
	gEngineMutex.Unlock()

	abl := (*C.AudioBufferList)(ioData)
	buffers := (*[2]C.AudioBuffer)(unsafe.Pointer(&abl.mBuffers[0]))[:2:2]

	for channel := 0; channel < 2; channel++ {
		buffer := buffers[channel]
		if buffer.mData == nil {
			continue
		}

		slice := (*[1 << 24]float32)(buffer.mData)[:frameCount:frameCount]

		if !trackMuted {
			for i := 0; i < frameCount; i++ {
				slice[i] = slice[i] * trackVolume
			}
		} else {
			for i := 0; i < frameCount; i++ {
				slice[i] = 0.0
			}
		}
	}

	return C.noErr
}

func parseBool(value string) (bool, error) {
	if value == "true" {
		return true, nil
	}
	if value == "false" {
		return false, nil
	}
	return false, fmt.Errorf("InvalidTrackState")
}

func parseTrackLine(line string) (int, Track, error) {
	colonIdx := strings.IndexByte(line, ':')
	if colonIdx == -1 {
		return 0, Track{}, fmt.Errorf("InvalidTrackState")
	}

	indexText := strings.TrimSpace(line[:colonIdx])
	rest := strings.TrimSpace(line[colonIdx+1:])

	parts := strings.Fields(rest)
	if len(parts) < 2 {
		return 0, Track{}, fmt.Errorf("InvalidTrackState")
	}

	volumePart := parts[0]
	mutedPart := parts[1]

	if !strings.HasPrefix(volumePart, "volume=") || !strings.HasPrefix(mutedPart, "muted=") {
		return 0, Track{}, fmt.Errorf("InvalidTrackState")
	}

	idx, err := strconv.Atoi(indexText)
	if err != nil {
		return 0, Track{}, err
	}

	vol, err := strconv.ParseFloat(volumePart[len("volume="):], 32)
	if err != nil {
		return 0, Track{}, err
	}

	muted, err := parseBool(mutedPart[len("muted="):])
	if err != nil {
		return 0, Track{}, err
	}

	return idx, Track{Volume: float32(vol), Muted: muted}, nil
}

func readTracks() ([2]Track, error) {
	file, err := os.Open(tracksStatePath)
	if err != nil {
		return [2]Track{}, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	if !scanner.Scan() {
		return [2]Track{}, fmt.Errorf("InvalidTrackState")
	}

	header := strings.TrimSpace(scanner.Text())
	if header != "tracks" {
		return [2]Track{}, fmt.Errorf("InvalidTrackState")
	}

	tracks := gTracks
	parsed := [2]bool{}

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		idx, track, err := parseTrackLine(line)
		if err != nil || idx == 0 || idx > len(tracks) {
			return [2]Track{}, fmt.Errorf("InvalidTrackState")
		}

		tracks[idx-1] = track
		parsed[idx-1] = true
	}

	for _, seen := range parsed {
		if !seen {
			return [2]Track{}, fmt.Errorf("InvalidTrackState")
		}
	}

	return tracks, nil
}

func loadTracksFromDisk() {
	tracks, err := readTracks()
	if err != nil {
		if os.IsNotExist(err) {
			return
		}
		fmt.Fprintf(os.Stderr, "Error reloading configuration: %v\n", err)
		return
	}

	gEngineMutex.Lock()
	gTracks = tracks
	gEngineMutex.Unlock()
}

func writeTracksSnapshot() error {
	file, err := os.Create(tracksStatePath)
	if err != nil {
		return err
	}
	defer file.Close()

	writer := bufio.NewWriter(file)
	_, _ = writer.WriteString("tracks\n")

	gEngineMutex.Lock()
	defer gEngineMutex.Unlock()

	for i, track := range gTracks {
		_, _ = fmt.Fprintf(writer, "%d: volume=%g muted=%t\n", i+1, track.Volume, track.Muted)
	}
	return writer.Flush()
}

func startDaemon() {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	var audioUnit C.AudioUnit

	status := C.initCoreAudio(&audioUnit)
	if status != C.noErr {
		fmt.Printf("Error: CoreAudio setup failed: %d\n", int(status))
		return
	}
	defer C.AudioComponentInstanceDispose(audioUnit)

	status = C.AudioOutputUnitStart(audioUnit)
	if status != C.noErr {
		fmt.Printf("Error: AudioUnit performance loop failed to start: %d\n", int(status))
		return
	}
	defer C.AudioOutputUnitStop(audioUnit)

	fmt.Println("DAW Backend Running via Native CoreAudio...")

	if err := writeTracksSnapshot(); err != nil {
		fmt.Printf("Initial state snapshot error: %v\n", err)
		return
	}

	for {
		time.Sleep(time.Second)
		loadTracksFromDisk()
	}
}

func listTracks() {
	file, err := os.Open(tracksStatePath)
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Println("DAW daemon track state not found. Run background service first.")
			return
		}
		fmt.Printf("Error: %v\n", err)
		return
	}
	defer file.Close()
	_, _ = io.Copy(os.Stdout, file)
}

func printTrackOneVolume() {
	tracks, err := readTracks()
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Println("DAW daemon track state not found. Run background service first.")
			return
		}
		return
	}
	fmt.Printf("track 1 volume=%g\n", tracks[0].Volume)
}

func writeTracks(tracks [2]Track) {
	gEngineMutex.Lock()
	previousTracks := gTracks
	gTracks = tracks
	gEngineMutex.Unlock()

	if err := writeTracksSnapshot(); err != nil {
		gEngineMutex.Lock()
		gTracks = previousTracks
		gEngineMutex.Unlock()
	}
}

func increaseTrackOneVolume(percentText string) {
	tracks, err := readTracks()
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Println("DAW daemon track state not found. Run background service first.")
			return
		}
		return
	}

	percent, err := strconv.ParseFloat(percentText, 32)
	if err != nil {
		fmt.Println("Invalid float increment value")
		return
	}

	tracks[0].Volume += float32(percent / 100.0)
	if tracks[0].Volume < 0.0 {
		tracks[0].Volume = 0.0
	}

	writeTracks(tracks)
	fmt.Printf("track 1 volume=%g\n", tracks[0].Volume)
}

func printUsage() {
	fmt.Print("Usage:\n  daw start\n  daw tracks list\n  daw tracks volume status\n  daw tracks volume increase <percent>\n\n")
}

func handleTracksCommand(args []string) {
	if len(args) >= 3 && args[2] == "list" {
		listTracks()
		return
	}

	if len(args) >= 4 && args[2] == "volume" {
		if args[3] == "status" {
			printTrackOneVolume()
			return
		}
		if args[3] == "increase" && len(args) >= 5 {
			increaseTrackOneVolume(args[4])
			return
		}
	}
	printUsage()
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		return
	}

	switch os.Args[1] {
	case "start":
		startDaemon()
	case "tracks":
		handleTracksCommand(os.Args)
	default:
		printUsage()
	}
}