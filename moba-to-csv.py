import csv
import os
import sys
import configparser
from collections import defaultdict

# Expanded list of session types found in MobaXterm files
SESSION_TYPES = {
    "#91#": "RDP",
    "#109#": "SSH",
    "#110#": "Telnet",
    "#114#": "RDP",
    "#115#": "VNC",
    "#116#": "FTP",
    "#117#": "SFTP",
    "#128#": "VNC",
    "#130#": "FTP",
}

def parse_session_line(session_name, data_string, folder_name):
    """
    Helper function to parse a single session data string and map it
    to Royal TS compatible column names.
    """
    try:
        # Split the data string by the '%' delimiter
        parts = data_string.split('%')
        
        # Extract the data based on the format
        host = parts[1]
        port = parts[2]
        user = parts[3]
        
        # Clean the username (e.g., [david] -> david)
        if user.startswith('[') and user.endswith(']'):
            user = user[1:-1]
            
        # Determine the session type from the code in parts[0]
        session_code = parts[0]
        session_type = "Unknown"
        for code, type_name in SESSION_TYPES.items():
            if code in session_code:
                session_type = type_name
                break
        
        # Moba uses '\', Royal TS uses '/' for nested folders
        royal_folder = folder_name.replace('\\', '/').strip()

        # Check for a private key file (for SSH)
        private_key = ""
        if session_type == "SSH" and len(parts) > 10 and ('.pem' in parts[10] or '.ppk' in parts[10]):
            # Clean up the Moba-specific profile directory variable
            private_key = parts[10].replace('_ProfileDir_', '%USERPROFILE%\\Documents\\MobaXterm\\')

        # Only return a dict if we have the essential info
        if host and user:
            # Map to Royal TS Column Names
            return {
                'Folder': royal_folder,
                'Name': session_name,
                'URI': host,
                'CredentialName': user,
                'Port': port,
                'Description': f"Imported from MobaXterm (Type: {session_type})",
                'PrivateKeyFile': private_key, # <-- NEW COLUMN
                '__Internal_Type': session_type # Internal key for file splitting
            }
    except IndexError:
        pass
    return None

def parse_moba_sessions_file(ini_file_path):
    """
    Parses a MobaXterm .mxtsessions file and returns a list of session dicts.
    """
    print(f"Parsing '{os.path.basename(ini_file_path)}'...")
    
    sessions = []
    
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
        return [] 

    for section in config.sections():
        folder_name = ""
        if section.startswith('Bookmarks_') or section == 'Bookmarks':
            folder_name = config[section].get('subrep', '') 
        
        for key, value in config[section].items():
            if key.lower() in ['subrep', 'imgnum']:
                continue
            
            session_data = parse_session_line(key, value, folder_name)
            if session_data:
                sessions.append(session_data)

    if not sessions:
        print("No valid sessions were found in the file.")
    
    return sessions

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
        print("-" * 30)
        input_file_path = os.path.join(script_dir, filename)
        base_name = os.path.splitext(input_file_path)[0]
        
        all_sessions = parse_moba_sessions_file(input_file_path)

        if not all_sessions:
            continue

        grouped_sessions = defaultdict(list)
        for session in all_sessions:
            grouped_sessions[session['__Internal_Type']].append(session)
        
        print(f"Found {len(all_sessions)} total sessions, grouped into {len(grouped_sessions)} types.")

        # Added 'PrivateKeyFile' to the headers
        headers = ['Folder', 'Name', 'URI', 'CredentialName', 'Port', 'Description', 'PrivateKeyFile']

        for session_type, sessions_list in grouped_sessions.items():
            # Create a type-specific filename (e.g., MySessions_SSH.csv)
            output_file_path = f"{base_name}_{session_type}.csv"
            
            try:
                with open(output_file_path, 'w', newline='', encoding='utf-8') as f:
                    writer = csv.DictWriter(f, fieldnames=headers, extrasaction='ignore')
                    writer.writeheader()
                    writer.writerows(sessions_list)
                
                print(f"Success! ✨ Exported {len(sessions_list)} {session_type} sessions to '{os.path.basename(output_file_path)}'")
            
            except IOError as e:
                print(f"Error writing CSV file '{os.path.basename(output_file_path)}': {e}")

    print("-" * 30)
    print("\nAll files processed.")

