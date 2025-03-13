#!/bin/bash

# File to store the fortunes
OUTPUT_FILE="fortune-quotes.js"

# Start the JavaScript array
echo "const fortunes = [" > $OUTPUT_FILE

# Generate 512 fortune quotes
for i in {1..512}
do
    FORTUNE=$(fortune -s | tr '\n' ' ' | sed 's/"/\\"/g')  # Get a short fortune and escape quotes
    echo "    \"$FORTUNE\"," >> $OUTPUT_FILE
done

# End the JavaScript array
echo "];" >> $OUTPUT_FILE

# Export a function to get a random fortune
echo "function getRandomFortune() { return fortunes[Math.floor(Math.random() * fortunes.length)]; }" >> $OUTPUT_FILE

echo "Generated $OUTPUT_FILE with 512 fortune quotes!"

