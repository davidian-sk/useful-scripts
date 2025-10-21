import csv
import os
import sys
import configparser

# MobaXterm session type codes. We can add more if you use them.
SESSION_TYPES = {
    "#109#": "SSH",
    "#117#": "SFTP",
    "#110#": "Telnet",
    "#114#": "RDP",
    "#115#": "VNC",
    "#116#": "FTP",
}

def parse_session_line(session_name, data_string, folder_name):
    """Helper function to parse a single session data string."""
    try:
        parts = data_string.split('%')
        host = parts[1]
        port = parts[2]
        user = parts[3]

        session_type = "Unknown"
        for code, type_name in SESSION_TYPES.items():
            if code in parts[0]:
                session_type = type_name
                break
        
        if host and user:
            return {
                'Folder': folder_name,
                'Name': session_name,
                'Type': session_type,
                'Host': host,
                'User': user,
                'Port': port
            }
    except IndexError:
        # This line is probably a folder or a malformed entry. Skip it.
        pass
    return None

def parse_moba_sessions_file(ini_file_path, csv_file_path):
    """
    Parses a MobaXterm .mxtsessions file, handling both flat and folder structures.
    """
    print(f"Parsing '{os.path.basename(ini_file_path)}'...")
    
    sessions = []
    
    # Use configparser for robust INI file handling
    config = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        config.read(ini_file_path, encoding='utf-8-sig')
    except Exception as e:
        print(f"Error reading file as INI: {e}")
        return

    # Process all sections in the file
    for section in config.sections():
        folder_name = ""
        # Sections like [Bookmarks_1] contain folders
        if section.startswith('Bookmarks_'):
            folder_name = config[section].get('subrep', '') # 'SubRep' holds the folder name
        
        # In Moba, every other key in the section is a session
        for key, value in config[section].items():
            # Skip the folder metadata keys
            if key.lower() in ['subrep', 'imgnum']:
                continue
            
            session_data = parse_session_line(key, value, folder_name)
            if session_data:
                sessions.append(session_data)

    if not sessions:
        print("No valid sessions were found in the file.")
        return

    # --- Write the data to the CSV file ---
    headers = ['Folder', 'Name', 'Type', 'Host', 'User', 'Port']
    
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

    session_files = []
    for filename in os.listdir(script_dir):
        if filename.lower().endswith('.mxtsessions'):
            session_files.append(filename)

    if not session_files:
        print(f"Error: No .mxtsessions files found in {script_dir} ❌")
        sys.exit(1)

    print(f"\nFound {len(session_files)} session file(s) to process.")
    
    for filename in session_files:
        print("-" * 30) # Add a separator for clarity
        input_file_path = os.path.join(script_dir, filename)
        
        base_name = os.path.splitext(input_file_path)[0]
        output_file_path = base_name + '.csv'
        
        parse_moba_sessions_file(input_file_path, output_file_path)

    print("-" * 30)
    print("\nAll files processed.")

