#!/usr/bin/env python3
"""
Parse Member List PDF to CSV

This script extracts table data from the Member List PDF and converts it to CSV format.
The PDF contains contact information with columns: Name, Gender, Age, Birthdate, Phone Number, and Email.
"""

import os
import sys
import csv
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
        logging.FileHandler(os.path.join(script_dir, 'parse_member_list_pdf.log'))
    ]
)
logger = logging.getLogger(__name__)

# Input and output paths
PDF_PATH = "/Users/andrewsoulier/Downloads/Member List.pdf"
CSV_PATH = "/Users/andrewsoulier/Downloads/Member List.csv"

# Expected columns
EXPECTED_COLUMNS = ["Name", "Gender", "Age", "Birthdate", "Phone Number", "Email"]


def normalize_column_name(col_name: str) -> str:
    """
    Normalize column names for case-insensitive matching.
    
    Args:
        col_name: Raw column name from PDF
    
    Returns:
        Normalized column name (lowercase, stripped)
    """
    return col_name.strip().lower() if col_name else ""


def find_column_mapping(headers: List[str]) -> Optional[Dict[int, str]]:
    """
    Map PDF table columns to expected column names.
    
    Args:
        headers: List of header strings from PDF table
    
    Returns:
        Dictionary mapping column index to expected column name, or None if mapping fails
    """
    # Normalize headers for matching
    normalized_headers = [normalize_column_name(h) for h in headers]
    
    # Create mapping of variations to expected column names
    # Map common variations to expected column names
    column_variations = {
        'name': 'Name',
        'gender': 'Gender',
        'age': 'Age',
        'birthdate': 'Birthdate',
        'birth date': 'Birthdate',  # Handle space in "Birth Date"
        'birthdate ': 'Birthdate',
        'phone number': 'Phone Number',
        'phone': 'Phone Number',
        'email': 'Email',
        'e-mail': 'Email',  # Handle hyphen in "E-mail"
        'e mail': 'Email',
        'email address': 'Email'
    }
    
    # Map column indices to expected column names
    column_mapping = {}
    
    for idx, header in enumerate(normalized_headers):
        # Remove extra spaces and check for matches
        cleaned_header = ' '.join(header.split())  # Normalize multiple spaces
        
        # Try to match against known variations
        for variation, expected_col in column_variations.items():
            if variation == cleaned_header or cleaned_header == variation:
                if idx not in column_mapping:  # Avoid duplicate mappings
                    column_mapping[idx] = expected_col
                    break
        
        # Also try substring matching if exact match failed
        if idx not in column_mapping:
            for variation, expected_col in column_variations.items():
                if variation in cleaned_header or cleaned_header in variation:
                    if idx not in column_mapping:
                        column_mapping[idx] = expected_col
                        break
    
    # Check if we found all required columns
    found_columns = set(column_mapping.values())
    expected_set = set(EXPECTED_COLUMNS)
    
    if found_columns != expected_set:
        missing = expected_set - found_columns
        logger.warning(f"Missing columns in header: {missing}")
        logger.info(f"Found headers: {normalized_headers}")
        logger.info(f"Column mapping: {column_mapping}")
        # Still proceed if we found most columns
    
    return column_mapping if column_mapping else None


def extract_table_from_pdf(pdf_path: str) -> List[List[str]]:
    """
    Extract table data from PDF file using pdfplumber.
    
    Args:
        pdf_path: Path to PDF file
    
    Returns:
        List of rows, where each row is a list of cell values
    """
    try:
        import pdfplumber
    except ImportError:
        logger.error("pdfplumber library not installed. Install it with: pip install pdfplumber")
        sys.exit(1)
    
    all_rows = []
    
    try:
        with pdfplumber.open(pdf_path) as pdf:
            logger.info(f"Opened PDF with {len(pdf.pages)} page(s)")
            
            for page_num, page in enumerate(pdf.pages, 1):
                logger.info(f"Processing page {page_num}...")
                
                # Extract tables from this page
                tables = page.extract_tables()
                
                if not tables:
                    logger.warning(f"No tables found on page {page_num}")
                    continue
                
                # Process each table on the page
                for table_num, table in enumerate(tables, 1):
                    logger.info(f"  Found table {table_num} on page {page_num} with {len(table)} rows")
                    
                    # Clean up table data (handle None values, strip whitespace)
                    cleaned_table = []
                    for row in table:
                        if row:  # Skip None rows
                            cleaned_row = [str(cell).strip() if cell else "" for cell in row]
                            cleaned_table.append(cleaned_row)
                    
                    if cleaned_table:
                        all_rows.extend(cleaned_table)
            
            logger.info(f"Total rows extracted: {len(all_rows)}")
            return all_rows
            
    except Exception as e:
        logger.error(f"Error extracting table from PDF: {e}")
        raise


def process_pdf_data(raw_rows: List[List[str]]) -> List[Dict[str, str]]:
    """
    Process raw table rows into structured data.
    
    Args:
        raw_rows: List of rows extracted from PDF
    
    Returns:
        List of dictionaries with column names as keys
    """
    if not raw_rows:
        logger.error("No rows found in PDF")
        return []
    
    # Find header row (should be first row with column names)
    header_row = None
    header_row_idx = 0
    
    for idx, row in enumerate(raw_rows):
        # Check if this row looks like headers (contains expected column names)
        row_text = " ".join([cell.lower() for cell in row if cell])
        if any(col.lower() in row_text for col in EXPECTED_COLUMNS):
            header_row = row
            header_row_idx = idx
            break
    
    if not header_row:
        # Use first row as header if we can't find a match
        logger.warning("Could not identify header row, using first row")
        header_row = raw_rows[0]
        header_row_idx = 0
    
    logger.info(f"Using row {header_row_idx + 1} as header: {header_row}")
    
    # Map columns
    column_mapping = find_column_mapping(header_row)
    
    if not column_mapping:
        logger.error("Failed to map columns to expected structure")
        return []
    
    logger.info(f"Column mapping established: {column_mapping}")
    
    # Process data rows (skip header row)
    data_rows = raw_rows[header_row_idx + 1:]
    processed_data = []
    
    for row_idx, row in enumerate(data_rows, start=header_row_idx + 2):
        if not row or all(not cell or cell.strip() == "" for cell in row):
            # Skip empty rows
            continue
        
        # Create dictionary for this row
        row_dict = {col: "" for col in EXPECTED_COLUMNS}  # Initialize all columns
        
        # Map values based on column mapping
        for pdf_col_idx, expected_col in column_mapping.items():
            if pdf_col_idx < len(row):
                value = row[pdf_col_idx].strip() if row[pdf_col_idx] else ""
                row_dict[expected_col] = value
        
        # Only add row if it has at least a name or phone/email
        if row_dict.get("Name") or row_dict.get("Phone Number") or row_dict.get("Email"):
            processed_data.append(row_dict)
        else:
            logger.debug(f"Skipping empty row {row_idx}")
    
    logger.info(f"Processed {len(processed_data)} data rows")
    return processed_data


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
    """Main function to parse PDF and create CSV"""
    logger.info("=" * 60)
    logger.info("Starting Member List PDF to CSV Conversion")
    logger.info("=" * 60)
    
    # Check if PDF file exists
    if not os.path.exists(PDF_PATH):
        logger.error(f"PDF file not found: {PDF_PATH}")
        return 1
    
    logger.info(f"Input PDF: {PDF_PATH}")
    logger.info(f"Output CSV: {CSV_PATH}")
    
    try:
        # Extract table data from PDF
        logger.info("Extracting table data from PDF...")
        raw_rows = extract_table_from_pdf(PDF_PATH)
        
        if not raw_rows:
            logger.error("No data extracted from PDF")
            return 1
        
        # Process data into structured format
        logger.info("Processing extracted data...")
        processed_data = process_pdf_data(raw_rows)
        
        if not processed_data:
            logger.error("No valid data rows found after processing")
            return 1
        
        # Write to CSV
        logger.info(f"Writing {len(processed_data)} rows to CSV...")
        if not write_csv(processed_data, CSV_PATH):
            return 1
        
        # Show sample of data
        logger.info("\nSample of extracted data (first 5 rows):")
        for i, row in enumerate(processed_data[:5], 1):
            logger.info(f"  {i}. {row}")
        
        logger.info("\n" + "=" * 60)
        logger.info("Conversion Complete!")
        logger.info("=" * 60)
        logger.info(f"  - Rows extracted: {len(processed_data)}")
        logger.info(f"  - Output file: {CSV_PATH}")
        logger.info("=" * 60)
        
        return 0
        
    except Exception as e:
        logger.error(f"Error during PDF processing: {e}")
        import traceback
        logger.error(traceback.format_exc())
        return 1


if __name__ == "__main__":
    sys.exit(main())

