# from PIL import Image
# import numpy as np
# import struct

# def process_image(input_image_path, output_binary_path, square_size):
#     # Open the image
#     with Image.open(input_image_path) as img:
#         # Resize the image to the desired square size
#         img = img.resize((square_size, square_size), Image.LANCZOS)
        
#         # Convert the image to RGBA format if it isn't already
#         img = img.convert("RGBA")
        
#         # Get pixel data as a numpy array
#         pixel_data = np.array(img)
        
#         # Prepare a binary file to store the raw data
#         with open(output_binary_path, "wb") as binary_file:
#             # Iterate through each pixel row by row
#             for row in pixel_data:
#                 for pixel in row:
#                     # Unpack RGBA values and pack them in little-endian format
#                     r, g, b, a = pixel
#                     binary_file.write(struct.pack('<BBBB', r, g, b, a))

# # Example usage
# input_image_path = 'input_image.jpg'   # Path to the input image
# output_binary_path = 'output_image_small.bin' # Path to the output binary file
# square_size = 256                       # Desired square size for the output

# process_image(input_image_path, output_binary_path, square_size)

from PIL import Image
import numpy as np
import struct

def process_image(input_image_path, output_binary_path, square_size):
    # Open the image
    with Image.open(input_image_path) as img:
        # Calculate the scale factor to fit the image within the square
        original_width, original_height = img.size
        scale = min(square_size / original_width, square_size / original_height)
        
        # Compute the new dimensions while maintaining the aspect ratio
        new_width = int(original_width * scale)
        new_height = int(original_height * scale)
        
        # Resize the image with the calculated dimensions
        resized_img = img.resize((new_width, new_height), Image.LANCZOS)
        
        # Create a black square image
        square_img = Image.new("RGBA", (square_size, square_size), (0, 0, 0, 255))
        
        # Compute the position to center the resized image in the square
        x_offset = (square_size - new_width) // 2
        y_offset = (square_size - new_height) // 2
        
        # Paste the resized image onto the square
        square_img.paste(resized_img, (x_offset, y_offset))
        
        # Get pixel data as a numpy array
        pixel_data = np.array(square_img)
        
        # Prepare a binary file to store the raw data
        with open(output_binary_path, "wb") as binary_file:
            # Iterate through each pixel row by row
            for row in pixel_data:
                for pixel in row:
                    # Unpack RGBA values and pack them in little-endian format
                    r, g, b, a = pixel
                    binary_file.write(struct.pack('<BBBB', r, g, b, a))

# Example usage
input_image_path = 'input_text_image.png'   # Path to the input image
output_binary_path = 'output_text_image.bin' # Path to the output binary file
square_size = 1024                       # Desired square size for the output

process_image(input_image_path, output_binary_path, square_size)
