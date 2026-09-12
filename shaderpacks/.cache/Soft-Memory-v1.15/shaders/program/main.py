import os
import re

# --- CONFIGURATION ---
# The folder where your files are ('.' means the current folder)
TARGET_DIR = '.'

# The highest numbered composite file you currently have
MAX_INDEX = 17

# The file number you want to start shifting from. 
# (e.g., If you are inserting a new pass at composite5, set this to 5. 
# It will shift 5->6, 6->7, etc., leaving a gap at 5).
START_INDEX = 2

# How many numbers to bump them up by
SHIFT_AMOUNT = 2


# ---------------------

def shift_shaders():
    print("Starting shader shift...")

    # We MUST loop backwards! If we go forwards, 5 becomes 6, and overwrites the real 6!
    for i in range(MAX_INDEX, START_INDEX - 1, -1):
        new_index = i + SHIFT_AMOUNT

        # Look for .fsh, .vsh, .csh, and .properties files
        for ext in ['.fsh', '.vsh', '.csh', '.properties']:
            old_filename = f"composite{i}{ext}"
            new_filename = f"composite{new_index}{ext}"

            old_filepath = os.path.join(TARGET_DIR, old_filename)
            new_filepath = os.path.join(TARGET_DIR, new_filename)

            # If the file exists, we process it
            if os.path.exists(old_filepath):
                # 1. Read the file and update the #include text inside
                with open(old_filepath, 'r', encoding='utf-8') as file:
                    content = file.read()

                # Replace the internal includes (e.g., "/program/composite5.fsh" -> "/program/composite6.fsh")
                # Using regex to catch it safely
                content = re.sub(rf'composite{i}\.fsh', f'composite{new_index}.fsh', content)
                content = re.sub(rf'composite{i}\.vsh', f'composite{new_index}.vsh', content)
                content = re.sub(rf'composite{i}\.csh', f'composite{new_index}.csh', content)

                # 2. Write the updated text back to the file
                with open(old_filepath, 'w', encoding='utf-8') as file:
                    file.write(content)

                # 3. Rename the actual file
                os.rename(old_filepath, new_filepath)
                print(f"✅ Renamed and updated: {old_filename} -> {new_filename}")

    print("Shift complete! Don't forget to update shaders.properties if needed.")


if __name__ == "__main__":
    shift_shaders()