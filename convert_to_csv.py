#!/usr/bin/env python3
"""
Convert CBT test results to CSV format
"""

import os
import sys
import json
import csv
import argparse
from pathlib import Path

def convert_json_to_csv(json_file, csv_file=None):
    """Convert JSON test results to CSV format"""
    
    if not os.path.exists(json_file):
        print(f"Error: JSON file {json_file} not found")
        return False
    
    # Read JSON data
    try:
        with open(json_file, 'r') as f:
            json_data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in {json_file}: {e}")
        return False
    except Exception as e:
        print(f"Error reading {json_file}: {e}")
        return False
    
    # Generate CSV filename if not provided
    if csv_file is None:
        csv_file = json_file.replace('.json', '.csv')
    
    # Prepare CSV data
    csv_data = []
    
    # Basic information
    csv_data.append(['Test Type', 'RADOS Bench'])
    csv_data.append(['Source File', json_file])
    csv_data.append(['', ''])  # Empty row
    
    # Performance metrics
    csv_data.append(['Metric', 'Value', 'Unit'])
    
    # Extract common metrics
    metrics = [
        ('Total Operations', 'Total writes made', 'ops'),
        ('Average IOPS', 'Average IOPS', 'IOPS'),
        ('IOPS Std Dev', 'Stddev IOPS', 'IOPS'),
        ('Average Latency', 'Average Latency', 'ms'),
        ('Bandwidth', 'Bandwidth', 'MB/s'),
        ('Max Latency', 'Max latency', 'ms'),
        ('Min Latency', 'Min latency', 'ms')
    ]
    
    for metric_name, json_key, unit in metrics:
        if json_key in json_data:
            csv_data.append([metric_name, json_data[json_key], unit])
    
    csv_data.append(['', ''])  # Empty row
    
    # All JSON data
    csv_data.append(['All JSON Data', '', ''])
    for key, value in json_data.items():
        csv_data.append([key, str(value), ''])
    
    # Write CSV file
    try:
        with open(csv_file, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerows(csv_data)
        
        print(f"Successfully converted {json_file} to {csv_file}")
        return True
        
    except Exception as e:
        print(f"Error writing CSV file {csv_file}: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Convert CBT test results to CSV format')
    parser.add_argument('input', help='Input JSON file or directory containing JSON files')
    parser.add_argument('-o', '--output', help='Output CSV file (for single file) or directory (for multiple files)')
    parser.add_argument('-r', '--recursive', action='store_true', help='Process directories recursively')
    
    args = parser.parse_args()
    
    input_path = Path(args.input)
    
    if input_path.is_file():
        # Single file
        output_file = args.output
        convert_json_to_csv(str(input_path), output_file)
        
    elif input_path.is_dir():
        # Directory
        output_dir = args.output
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir)
        
        # Find JSON files
        pattern = "**/*.json" if args.recursive else "*.json"
        json_files = list(input_path.glob(pattern))
        
        if not json_files:
            print(f"No JSON files found in {input_path}")
            return
        
        print(f"Found {len(json_files)} JSON files")
        
        for json_file in json_files:
            if output_dir:
                # Create output filename preserving directory structure
                rel_path = json_file.relative_to(input_path)
                csv_file = Path(output_dir) / rel_path.with_suffix('.csv')
                csv_file.parent.mkdir(parents=True, exist_ok=True)
                convert_json_to_csv(str(json_file), str(csv_file))
            else:
                convert_json_to_csv(str(json_file))
    
    else:
        print(f"Error: {input_path} is not a valid file or directory")
        sys.exit(1)

if __name__ == '__main__':
    main()
