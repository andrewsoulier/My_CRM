#!/usr/bin/env python3
"""
Parse Stake Data RTF to CSV

This script extracts contact information from an RTF file containing stake member data
and converts it to CSV format with columns: Name, Gender, Age, Birth Date, Phone Number, and Email.
"""

import os
import sys
import csv
import re
import logging
from pathlib import Path
from typing import List, Dict, Optional

# Configure logging
script_dir = os.path.dirname(os.path.abspath(__file__))
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(os.path.join(script_dir, 'parse_stake_data_rtf.log'))
    ]
)
logger = logging.getLogger(__name__)

# Input and output paths
RTF_PATH = "/Users/andrewsoulier/Downloads/Stake Data.rtf"
CSV_PATH = "/Users/andrewsoulier/Downloads/Stake Data.csv"

# Expected columns
EXPECTED_COLUMNS = ["Name", "Gender", "Age", "Birth Date", "Phone Number", "Email"]

# Month abbreviations
MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']


def extract_text_from_rtf(rtf_path: str) -> str:
    """
    Extract plain text from RTF file.
    
    Args:
        rtf_path: Path to RTF file
    
    Returns:
        Plain text content
    """
    try:
        with open(rtf_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # Find the start of actual content (after \strokec2)
        start_idx = content.find('\\strokec2')
        if start_idx != -1:
            text = content[start_idx + len('\\strokec2'):]
        else:
            text = content
        
        # Remove RTF special character encodings
        text = text.replace('\\\'f1', 'ñ')  # Handle special characters like ñ
        text = text.replace('\\\'e1', 'á')
        text = text.replace('\\\'e9', 'é')
        text = text.replace('\\\'ed', 'í')
        text = text.replace('\\\'f3', 'ó')
        text = text.replace('\\\'fa', 'ú')
        
        # Remove RTF control sequences and braces
        text = re.sub(r'\\[a-zA-Z]+\d*\s*', ' ', text)
        text = re.sub(r'\{[^}]*\}', '', text)
        text = re.sub(r'\}', '', text)
        
        # Clean up whitespace but preserve single spaces
        text = ' '.join(text.split())
        
        return text
        
    except Exception as e:
        logger.error(f"Error reading RTF file: {e}")
        raise


def parse_record(record_text: str) -> Optional[Dict[str, str]]:
    """
    Parse a single record from the text stream.
    
    Format: Last, First [Middle] Gender Age Day Month Year [Phone] [Email]
    
    Args:
        record_text: Text string containing a single record
    
    Returns:
        Dictionary with parsed fields, or None if parsing fails
    """
    # Pattern: Last, First [Middle Names] Gender Age Day Month Year [Phone] [Email]
    # Phone and Email are optional
    
    # First try pattern with phone/email
    pattern_with_data = r'^([A-Z][a-zA-Z\s\',\-()]+?),\s+([A-Z][a-zA-Z\s\',\-()]+?)\s+([MF])\s+(\d+)\s+(\d+)\s+([A-Z][a-z]{2})\s+(\d{4})\s+(.+)$'
    
    # Pattern without phone/email (ends after year)
    pattern_no_data = r'^([A-Z][a-zA-Z\s\',\-()]+?),\s+([A-Z][a-zA-Z\s\',\-()]+?)\s+([MF])\s+(\d+)\s+(\d+)\s+([A-Z][a-z]{2})\s+(\d{4})\s*$'
    
    match = re.match(pattern_with_data, record_text)
    if not match:
        # Try pattern without phone/email
        match = re.match(pattern_no_data, record_text)
        if match:
            last_name = match.group(1).strip()
            first_and_middle = match.group(2).strip()
            gender = match.group(3)
            age = match.group(4)
            day = match.group(5)
            month = match.group(6)
            year = match.group(7)
            
            return {
                "Name": f"{last_name}, {first_and_middle}",
                "Gender": gender,
                "Age": age,
                "Birth Date": f"{day} {month} {year}",
                "Phone Number": "",
                "Email": ""
            }
        return None
    
    last_name = match.group(1).strip()
    first_and_middle = match.group(2).strip()
    gender = match.group(3)
    age = match.group(4)
    day = match.group(5)
    month = match.group(6)
    year = match.group(7)
    rest = match.group(8).strip()
    
    # Combine name
    name = f"{last_name}, {first_and_middle}"
    
    # Format birth date
    birth_date = f"{day} {month} {year}"
    
    # Extract phone and email from rest
    phone = ""
    email = ""
    
    # Email pattern - look for email address
    email_pattern = r'\b([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})\b'
    email_match = re.search(email_pattern, rest)
    
    if email_match:
        email = email_match.group(1)
        # Phone is everything before email
        phone = rest[:email_match.start()].strip()
    else:
        # No email, rest might be phone or next record
        # Look for pattern that indicates next record: "Last, First" where Last starts with capital
        next_record_pattern = r'\s+([A-Z][a-zA-Z]+),\s+[A-Z]'
        next_match = re.search(next_record_pattern, rest)
        if next_match:
            # Phone is everything before next record
            phone = rest[:next_match.start()].strip()
        else:
            # No next record, rest is phone (might be empty)
            phone = rest.strip()
    
    return {
        "Name": name,
        "Gender": gender,
        "Age": age,
        "Birth Date": birth_date,
        "Phone Number": phone,
        "Email": email
    }


def parse_all_records(text: str) -> List[Dict[str, str]]:
    """
    Parse all records from the text.
    
    Args:
        text: Full text content
    
    Returns:
        List of parsed records
    """
    records = []
    
    # Split text into individual records
    # A record starts with: Last, First (capital letter, comma, space, capital letter)
    # We'll find all positions where a new record starts
    
    # Pattern to find record boundaries: "Last, First" where Last starts with capital
    # This pattern appears at the start of each record
    # The pattern should match up to the year, with optional whitespace after
    record_start_pattern = r'([A-Z][a-zA-Z\s\',\-()]+?,\s+[A-Z][a-zA-Z\s\',\-()]+?\s+[MF]\s+\d+\s+\d+\s+[A-Z][a-z]{2}\s+\d{4}\s*)'
    
    # Find all record starts
    matches = list(re.finditer(record_start_pattern, text))
    
    if not matches:
        logger.error("No records found matching the expected pattern")
        return records
    
    logger.info(f"Found {len(matches)} potential records")
    
    # Process each record
    for i, match in enumerate(matches):
        start_pos = match.start()
        
        # Determine end position (start of next record or end of text)
        if i + 1 < len(matches):
            end_pos = matches[i + 1].start()
        else:
            end_pos = len(text)
        
        record_text = text[start_pos:end_pos].strip()
        
        # Parse the record
        parsed = parse_record(record_text)
        if parsed:
            records.append(parsed)
        else:
            logger.warning(f"Failed to parse record {i+1}: {record_text[:100]}...")
    
    return records


def write_csv(data: List[Dict[str, str]], csv_path: str) -> bool:
    """
    Write processed data to CSV file.
    
    Args:
        data: List of dictionaries with contact data
        csv_path: Path to output CSV file
    
    Returns:
        True if successful, False otherwise
    """
    try:
        with open(csv_path, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=EXPECTED_COLUMNS, extrasaction='ignore')
            
            # Write header
            writer.writeheader()
            
            # Write data rows
            for row in data:
                writer.writerow(row)
        
        logger.info(f"Successfully wrote {len(data)} rows to {csv_path}")
        return True
        
    except Exception as e:
        logger.error(f"Error writing CSV file: {e}")
        return False


def main():
    """Main function to parse RTF and create CSV"""
    logger.info("=" * 60)
    logger.info("Starting Stake Data RTF to CSV Conversion")
    logger.info("=" * 60)
    
    # Check if RTF file exists
    if not os.path.exists(RTF_PATH):
        logger.error(f"RTF file not found: {RTF_PATH}")
        return 1
    
    logger.info(f"Input RTF: {RTF_PATH}")
    logger.info(f"Output CSV: {CSV_PATH}")
    
    try:
        # Extract text from RTF
        logger.info("Extracting text from RTF file...")
        text = extract_text_from_rtf(RTF_PATH)
        logger.info(f"Extracted {len(text)} characters of text")
        
        # Parse records
        logger.info("Parsing records from text...")
        records = parse_all_records(text)
        
        if not records:
            logger.error("No records found in text")
            # Try alternative parsing approach
            logger.info("Trying alternative parsing approach...")
            # Split by common patterns and try again
            return 1
        
        logger.info(f"Parsed {len(records)} records")
        
        # Write to CSV
        logger.info(f"Writing {len(records)} rows to CSV...")
        if not write_csv(records, CSV_PATH):
            return 1
        
        # Show sample of data
        logger.info("\nSample of extracted data (first 5 rows):")
        for i, row in enumerate(records[:5], 1):
            logger.info(f"  {i}. {row}")
        
        logger.info("\n" + "=" * 60)
        logger.info("Conversion Complete!")
        logger.info("=" * 60)
        logger.info(f"  - Records extracted: {len(records)}")
        logger.info(f"  - Output file: {CSV_PATH}")
        logger.info("=" * 60)
        
        return 0
        
    except Exception as e:
        logger.error(f"Error during RTF processing: {e}")
        import traceback
        logger.error(traceback.format_exc())
        return 1


if __name__ == "__main__":
    sys.exit(main())

