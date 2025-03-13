#!/bin/bash

# File to store the fortunes
OUTPUT_FILE="fortunes.js"

# Start the JavaScript array
echo "const fortunes = [" > $OUTPUT_FILE

# Generate 200 fortune quotes
for i in {1..200}
do
    FORTUNE=$(fortune -s | tr '\n' ' ' | sed 's/"/\\"/g')  # Get a short fortune and escape quotes
    echo "    \"$FORTUNE\"," >> $OUTPUT_FILE
done

# End the JavaScript array
echo "];" >> $OUTPUT_FILE

# Export a function to get a random fortune
echo "function getRandomFortune() { return fortunes[Math.floor(Math.random() * fortunes.length)]; }" >> $OUTPUT_FILE

echo "Generated $OUTPUT_FILE with 200 fortune quotes!"

