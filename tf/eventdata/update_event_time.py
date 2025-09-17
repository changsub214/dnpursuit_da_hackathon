import json
import os
import random
import datetime
import subprocess
import sys

# --- Configuration ---
INPUT_JSON_FILE = "recent_retail_events.json"  # Original JSON file path
TEMP_OUTPUT_FILE = "temp_modified_events_python.json"
# The output filename on GCS will be the same as INPUT_JSON_FILE

def get_gcs_full_path():
    """Gets the full GCS output path from an environment variable."""
    gcs_bucket_path_env = os.environ.get("GCS_BUCKET_PATH")
    if not gcs_bucket_path_env:
        print("Error: Environment variable 'GCS_BUCKET_PATH' is not set for the GCS bucket path.", file=sys.stderr)
        print("Example: export GCS_BUCKET_PATH=\"your-bucket-name/some/path\" or \"gs://your-bucket-name/some/path\"", file=sys.stderr)
        sys.exit(1)

    target_gcs_prefix = ""
    if gcs_bucket_path_env.startswith("gs://"):
        target_gcs_prefix = gcs_bucket_path_env
    else:
        target_gcs_prefix = f"gs://{gcs_bucket_path_env}"

    # Ensure there's a single slash between the bucket path and the filename
    if not target_gcs_prefix.endswith("/"):
        return f"{target_gcs_prefix}/{INPUT_JSON_FILE}"
    else:
        return f"{target_gcs_prefix}{INPUT_JSON_FILE}"

def count_lines_in_file(filename):
    """Counts the total number of lines in a file."""
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            return sum(1 for _ in f)
    except FileNotFoundError:
        print(f"Error: Input file '{filename}' not found.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error counting lines in '{filename}': {e}", file=sys.stderr)
        sys.exit(1)

def main():
    gcs_full_output_path = get_gcs_full_path()

    if not os.path.exists(INPUT_JSON_FILE):
        print(f"Error: Input file '{INPUT_JSON_FILE}' not found.", file=sys.stderr)
        sys.exit(1)

    total_lines = count_lines_in_file(INPUT_JSON_FILE)
    if total_lines == 0:
        print(f"Warning: Input file '{INPUT_JSON_FILE}' is empty. No data to process.")
        # Optionally, upload an empty file or exit
        # For now, an empty temp file will be created and uploaded if gsutil is called

    print(f"Input file: {INPUT_JSON_FILE}")
    print(f"GCS Bucket Path (from env GCS_BUCKET_PATH): {os.environ.get('GCS_BUCKET_PATH')}")
    print(f"GCS Output Filename: {INPUT_JSON_FILE}")
    print(f"Full GCS Target Path: {gcs_full_output_path}")
    print(f"Temporary file: {TEMP_OUTPUT_FILE}")
    if total_lines > 0:
        print(f"INFO: Total lines to process: {total_lines}")
    print("Starting event time modification...")

    # Get current UTC date to base "days ago" calculations on consistently
    today_utc = datetime.datetime.now(datetime.timezone.utc).date()
    processed_lines = 0

    try:
        with open(INPUT_JSON_FILE, 'r', encoding='utf-8') as infile, \
             open(TEMP_OUTPUT_FILE, 'w', encoding='utf-8') as outfile:

            if total_lines == 0: # Handle empty input file
                pass # Temp file will remain empty
            else:
                for i, line_str in enumerate(infile):
                    current_line_number = i + 1
                    try:
                        data = json.loads(line_str)

                        days_ago = 0
                        if total_lines > 1:
                            # Linear distribution from 35 days ago (oldest, line 1)
                            # to 0 days ago (newest, line total_lines)
                            days_ago_float = 35.0 * (total_lines - current_line_number) / (total_lines - 1)
                            days_ago = round(days_ago_float)
                        elif total_lines == 1: # Single line file, eventTime will be today
                            days_ago = 0
                        # If total_lines is 0, this loop won't run.

                        new_date_dt = today_utc - datetime.timedelta(days=int(days_ago))

                        # Generate random time components
                        rand_hour = random.randint(0, 23)
                        rand_minute = random.randint(0, 59)
                        rand_second = random.randint(0, 59)
                        # Generate 6 random digits for microseconds for .xxxxxxZ format
                        rand_microsecond = random.randint(0, 999999)

                        new_datetime_dt = datetime.datetime(
                            new_date_dt.year, new_date_dt.month, new_date_dt.day,
                            rand_hour, rand_minute, rand_second, rand_microsecond,
                            tzinfo=datetime.timezone.utc # Explicitly UTC
                        )

                        # Format to ISO 8601 with 'Z' and 6 microsecond digits
                        new_event_time_str = f"{new_datetime_dt.strftime('%Y-%m-%dT%H:%M:%S')}.{new_datetime_dt.strftime('%f')}Z"

                        data['eventTime'] = new_event_time_str
                        outfile.write(json.dumps(data) + '\n')

                    except json.JSONDecodeError:
                        print(f"Warning: Could not decode JSON on line {current_line_number}. Writing original line.", file=sys.stderr)
                        outfile.write(line_str) # Write original line if it's not valid JSON
                    except Exception as e:
                        print(f"Warning: Error processing line {current_line_number}: {e}. Writing original line.", file=sys.stderr)
                        outfile.write(line_str)

                    processed_lines += 1
                    if processed_lines > 0 and processed_lines % 1000 == 0:
                        print(f"{processed_lines} lines processed...")
    except Exception as e:
        print(f"Error during file processing: {e}", file=sys.stderr)
        sys.exit(1)

    if total_lines > 0 : # Only print this if lines were actually processed
        print(f"Total {processed_lines} lines processed.")
    print(f"Uploading modified file to GCS: {gcs_full_output_path}")

    try:
        subprocess.run(["gsutil", "cp", TEMP_OUTPUT_FILE, gcs_full_output_path], check=True, capture_output=True)
        print("GCS upload successful.")
    except subprocess.CalledProcessError as e:
        print(f"Error: GCS upload failed. gsutil stderr: {e.stderr.decode()}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print("Error: 'gsutil' command not found. Make sure Google Cloud SDK is installed and in your PATH.", file=sys.stderr)
        sys.exit(1)

    try:
        os.remove(TEMP_OUTPUT_FILE)
        print(f"Temporary file '{TEMP_OUTPUT_FILE}' deleted.")
    except OSError as e:
        print(f"Warning: Could not delete temporary file '{TEMP_OUTPUT_FILE}': {e}", file=sys.stderr)

    print("Script execution completed.")

if __name__ == "__main__":
    main()