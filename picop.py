from PIL import Image

img = Image.open("./assets/img/makesim/dffexp.png")

width, height = img.size
new_size = (width // 2, height // 2)
output_img = img.resize(new_size, Image.LANCZOS)

# Save to a new file
output_img.save("./assets/img/makesim/dffexp.1.png")

