import csv
import os
import sys

# MobaXterm session type codes. We can add more if you use them.
SESSION_TYPES = {
    "#109#": "SSH",
    "#117#": "SFTP",
    "#110#": "Telnet",
    "#114#": "RDP",
    "#115#": "VNC",
    "#116#": "FTP",
}

def parse_moba_sessions_file(ini_file_path, csv_file_path):
    """
    Parses a MobaXterm .mxtsessions file with the single-line bookmark format.
    """
    print(f"Parsing '{os.path.basename(ini_file_path)}'...")
    
    sessions = []
    in_bookmarks_section = False

    try:
        # We need to read the file manually, line by line
        with open(ini_file_path, 'r', encoding='utf-8-sig') as f:
            for line in f:
                line = line.strip()

                if line == '[Bookmarks]':
                    in_bookmarks_section = True
                    continue

                # If we are in the [Bookmarks] section and the line is a session...
                if in_bookmarks_section and '=' in line:
                    # Skip the file's own metadata
                    if line.startswith('SubRep=') or line.startswith('ImgNum='):
                        continue
                        
                    try:
                        # Split the line into "Name" and "Data"
                        name, data_string = line.split('=', 1)
                        
                        # Split the data string by the '%' delimiter
                        parts = data_string.split('%')

                        # From your sample, the data is at these positions:
                        # parts[1] is Host, parts[2] is Port, parts[3] is User
                        host = parts[1]
                        port = parts[2]
                        user = parts[3]

                        # Determine the session type from the code in parts[0]
                        session_type = "Unknown"
                        for code, type_name in SESSION_TYPES.items():
                            if code in parts[0]:
                                session_type = type_name
                                break
                        
                        # We only want to save entries that look like real sessions
                        if host and user:
                            sessions.append({
                                'Name': name,
                                'Type': session_type,
                                'Host': host,
                                'User': user,
                                'Port': port
                            })

                    except IndexError:
                        # This line is probably a folder or a malformed entry. Skip it.
                        pass
                    except Exception as e:
                        print(f"Error parsing line: {line}\n{e}")

    except Exception as e:
        print(f"Error reading file: {e}")
        return

    if not sessions:
        print("No valid sessions were found in the [Bookmarks] section.")
        return

    # --- Write the data to the CSV file ---
    headers = ['Name', 'Type', 'Host', 'User', 'Port']
    
    try:
        with open(csv_file_path, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=headers)
            writer.writeheader()
            writer.writerows(sessions)
        
        print(f"Success! ✨ Exported {len(sessions)} sessions to '{os.path.basename(csv_file_path)}'")

    except IOError as e:
        print(f"Error writing CSV file: {e}")

# --- Run the script ---
if __name__ == "__main__":
    
    try:
        script_dir = os.path.dirname(os.path.realpath(__file__))
    except NameError:
        script_dir = os.getcwd()

    print(f"Script is running in: {script_dir}")

    # --- NEW: Find ALL .mxtsessions files ---
    session_files = []
    for filename in os.listdir(script_dir):
        if filename.lower().endswith('.mxtsessions'):
            session_files.append(filename)

    if not session_files:
        print(f"Error: No .mxtsessions files found in {script_dir} ❌")
        sys.exit(1)

    print(f"\nFound {len(session_files)} session file(s) to process.")
    
    # --- NEW: Loop through each file and process it ---
    for filename in session_files:
        print("-" * 30) # Add a separator for clarity
        input_file_path = os.path.join(script_dir, filename)
        
        # Create the output .csv path based on the input file's name
        base_name = os.path.splitext(input_file_path)[0]
        output_file_path = base_name + '.csv'
        
        # Run the parser function for the current file
        parse_moba_sessions_file(input_file_path, output_file_path)

    print("-" * 30)
    print("\nAll files processed.")
