import os
import sys

def replace_user_in_sessions(input_file_path, output_file_path, old_user, new_user):
    """
    Reads a MobaXterm sessions file, replaces a username, and saves it to a new file.
    """
    print(f"Processing '{os.path.basename(input_file_path)}'...")
    
    lines_changed = 0
    
    try:
        # Open the original file for reading and a new file for writing
        with open(input_file_path, 'r', encoding='utf-8-sig') as infile, \
             open(output_file_path, 'w', encoding='utf-8') as outfile:
            
            in_bookmarks_section = False
            for line in infile:
                original_line = line.strip()
                
                # We only want to modify lines inside the [Bookmarks] section
                if original_line == '[Bookmarks]':
                    in_bookmarks_section = True
                    # Write the header and continue
                    outfile.write(original_line + '\n')
                    continue
                
                # Check if the line is a session entry we can modify
                if in_bookmarks_section and '=' in original_line and not (original_line.startswith('SubRep=') or original_line.startswith('ImgNum=')):
                    try:
                        name, data_string = original_line.split('=', 1)
                        parts = data_string.split('%')
                        
                        # The username is at index 3. Check if it matches the old user.
                        current_user = parts[3]
                        if current_user == old_user:
                            print(f"  - Found user '{old_user}' in session: {name}. Replacing with '{new_user}'.")
                            parts[3] = new_user  # Perform the replacement
                            
                            # Rebuild the line
                            new_data_string = '%'.join(parts)
                            new_line = f"{name}={new_data_string}"
                            outfile.write(new_line + '\n')
                            lines_changed += 1
                        else:
                            # If the user doesn't match, write the original line back
                            outfile.write(original_line + '\n')

                    except (IndexError, ValueError):
                        # This line is probably a folder or malformed, write it back as-is
                        outfile.write(original_line + '\n')
                else:
                    # For any other line (headers, blank lines), write it back unchanged
                    outfile.write(original_line + '\n')
        
        if lines_changed > 0:
            print(f"Success! ✨ Replaced the username in {lines_changed} session(s).")
            print(f"New file saved as: '{os.path.basename(output_file_path)}'")
        else:
            print(f"Operation complete. No sessions found with the username '{old_user}'.")
            # Clean up the empty output file if nothing was changed
            os.remove(output_file_path)

    except IOError as e:
        print(f"Error reading or writing file: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

# --- Run the script ---
if __name__ == "__main__":
    
    try:
        script_dir = os.path.dirname(os.path.realpath(__file__))
    except NameError:
        script_dir = os.getcwd()

    print(f"Script is running in: {script_dir}")

    session_files = []
    for filename in os.listdir(script_dir):
        if filename.lower().endswith('.mxtsessions'):
            session_files.append(filename)

    if not session_files:
        print(f"Error: No .mxtsessions files found in {script_dir} ❌")
        sys.exit(1)

    print(f"\nFound {len(session_files)} session file(s) to process.")

    # --- NEW: Ask user for the mode if there are multiple files ---
    ask_once = False
    if len(session_files) > 1:
        choice = input("Use the same usernames for all files? (yes/no): ").lower()
        if choice in ['yes', 'y']:
            ask_once = True

    old_username = ''
    new_username = ''

    # If asking once, get the usernames before the loop
    if ask_once:
        print("-" * 40)
        old_username = input("Enter the OLD username to replace in ALL files: ")
        new_username = input("Enter the NEW username to use: ")
        if not old_username or not new_username:
            print("\nError: Both old and new usernames are required. Exiting.")
            sys.exit(1)

    # --- Loop through each file and process it ---
    for filename in session_files:
        print("-" * 40)
        input_file_path = os.path.join(script_dir, filename)
        
        # If asking for each file, get usernames inside the loop
        if not ask_once:
            print(f"Configuring replacements for: {filename}")
            old_username = input("Enter the OLD username (or press Enter to skip): ")
            if not old_username:
                print("Skipping file.")
                continue # Go to the next file
            new_username = input("Enter the NEW username: ")
            if not new_username:
                print("NEW username cannot be empty. Skipping file.")
                continue
        
        # Create the output file path
        base_name, extension = os.path.splitext(input_file_path)
        output_file_path = f"{base_name}_updated{extension}"
        
        # Run the replacement function for the current file
        replace_user_in_sessions(input_file_path, output_file_path, old_username, new_username)

    print("-" * 40)
    print("\nAll files processed.")

