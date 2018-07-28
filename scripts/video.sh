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
        }" \
    ) \
    -i audio.mp3 \
    -vf scale=1280x720 \
    video.mp4
