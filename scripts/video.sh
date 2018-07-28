#!/bin/bash

ffmpeg \
    -y \
    -f concat \
    -safe 0 \
    -i <( \
        <timing \
        awk -F : "{
            print \"file '$(pwd)/slide-\" NR-1 \".png'\";
            print \"duration \" \$1*60+\$2-t;
            t=\$1*60+\$2;
        }
        END{
            print \"file '$(pwd)/slide-\" NR-1 \".png'\";
        }" \
    ) \
    -i audio.mp3 \
    -vf format=yuv420p,scale=1280x720 \
    video.mp4
