import csv
import os
import sys
import configparser
from collections import defaultdict

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
        # Split the data string by the '%' delimiter
        parts = data_string.split('%')
        
        # Extract the data based on the format
        host = parts[1]
        port = parts[2]
        user = parts[3]

        # Determine the session type from the code in parts[0]
        session_type = "Unknown"
        for code, type_name in SESSION_TYPES.items():
            if code in parts[0]:
                session_type = type_name
                break
        
        # Only return a dict if we have the essential info
        if host and user:
            return {
                'Folder': folder_name,
                'Name': session_name,
                'Type': session_type,
                'Host': host, # <-- Reverted: Removed the leading single quote
                'User': user,
                'Port': port
            }
    except IndexError:
        # This line is probably a folder or a malformed entry. Skip it.
        pass
    return None

def parse_moba_sessions_file(ini_file_path):
    """
    Parses a MobaXterm .mxtsessions file and returns a list of session dicts.
    """
    print(f"Parsing '{os.path.basename(ini_file_path)}'...")
    
    sessions = []
    
    # Use configparser for robust INI file handling
    # We MUST disable comment prefixes, otherwise it treats the session data 
    # (which starts with '#') as a comment and ignores the entire line.
    config = configparser.ConfigParser(
        interpolation=None, 
        strict=False, 
        comment_prefixes=(), 
        inline_comment_prefixes=()
    )
    
    try:
        config.read(ini_file_path, encoding='utf-8-sig')
    except Exception as e:
        print(f"Error reading file as INI: {e}")
        return [] # Return an empty list on error

    # Process all sections in the file (e.g., [Bookmarks], [Bookmarks_1], etc.)
    for section in config.sections():
        folder_name = ""
        # Sections like [Bookmarks_1] contain folders
        # We check the 'subrep' key for the folder name
        if section.startswith('Bookmarks_'):
            folder_name = config[section].get('subrep', '') 
        
        # In Moba, every other key in the section is a session
        for key, value in config[section].items():
            # Skip the folder metadata keys ('subrep' and 'imgnum')
            if key.lower() in ['subrep', 'imgnum']:
                continue
            
            # Parse the session line (e.g., "alpine-lxc" = "#109#0%192...")
            session_data = parse_session_line(key, value, folder_name)
            if session_data:
                sessions.append(session_data)

    if not sessions:
        print("No valid sessions were found in the file.")
    
    return sessions

# --- Run the script ---
if __name__ == "__main__":
    
    try:
        # Get the directory where the script is located
        script_dir = os.path.dirname(os.path.realpath(__file__))
    except NameError:
        # Fallback for interactive consoles
        script_dir = os.getcwd()

    print(f"Script is running in: {script_dir}")

    # Find all .mxtsessions files in that directory
    session_files = []
    for filename in os.listdir(script_dir):
        if filename.lower().endswith('.mxtsessions'):
            session_files.append(filename)

    # Exit if no files are found
    if not session_files:
        print(f"Error: No .mxtsessions files found in {script_dir} ❌")
        sys.exit(1)

    print(f"\nFound {len(session_files)} session file(s) to process.")
    
    # Loop through each found file and process it
    for filename in session_files:
        print("-" * 30) # Add a separator for clarity
        input_file_path = os.path.join(script_dir, filename)
        
        # Get the base name for output files (e.g., "MyFile.mxtsessions" -> "MyFile")
        base_name = os.path.splitext(input_file_path)[0]
        
        # Run the parser function to get all sessions from the file
        all_sessions = parse_moba_sessions_file(input_file_path)

        if not all_sessions:
            continue # Skip to the next file if this one was empty

        # Group sessions by type (e.g., 'SSH', 'SFTP')
        grouped_sessions = defaultdict(list)
        for session in all_sessions:
            grouped_sessions[session['Type']].append(session)
        
        print(f"Found {len(all_sessions)} total sessions, grouped into {len(grouped_sessions)} types.")

        # Define the headers for the CSV
        headers = ['Folder', 'Name', 'Type', 'Host', 'User', 'Port']

        # Loop through each group and write a separate CSV
        for session_type, sessions_list in grouped_sessions.items():
            # Create a unique filename for this type, e.g., "MyFile_SSH.csv"
            output_file_path = f"{base_name}_{session_type}.csv"
            
            try:
                with open(output_file_path, 'w', newline='', encoding='utf-8') as f:
                    writer = csv.DictWriter(f, fieldnames=headers)
                    writer.writeheader()
                    writer.writerows(sessions_list)
                
                print(f"Success! ✨ Exported {len(sessions_list)} {session_type} sessions to '{os.path.basename(output_file_path)}'")
            
            except IOError as e:
                print(f"Error writing CSV file '{os.path.basename(output_file_path)}': {e}")

    print("-" * 30)
    print("\nAll files processed.")

