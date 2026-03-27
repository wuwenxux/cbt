#!/usr/bin/env python3
"""
Parse rados bench output and convert to CSV format
"""

import re
import csv
import sys
import argparse

def parse_rados_bench_output(output_text):
    """Parse rados bench output text and extract metrics"""
    
    # Initialize result dictionary
    result = {}
    
    # Parse the summary section at the end
    lines = output_text.strip().split('\n')
    
    # Find the summary section (starts with "Total time run:")
    summary_start = -1
    for i, line in enumerate(lines):
        if line.startswith("Total time run:"):
            summary_start = i
            break
    
    if summary_start == -1:
        print("Error: Could not find summary section in output")
        return None
    
    # Parse summary metrics
    summary_lines = lines[summary_start:]
    for line in summary_lines:
        if ':' in line:
            key, value = line.split(':', 1)
            key = key.strip()
            value = value.strip()
            
            # Convert numeric values
            try:
                if '.' in value:
                    result[key] = float(value)
                else:
                    result[key] = int(value)
            except ValueError:
                result[key] = value
    
    # Parse the real-time data (if needed)
    # Look for the table data
    table_data = []
    for line in lines:
        # Match lines like "    1       1         2         1 0.00389313 0.00390625    0.856389    0.856389"
        if re.match(r'^\s*\d+\s+\d+\s+\d+\s+\d+\s+[\d.]+\s+[\d.]+\s+[\d.]+\s+[\d.]+', line):
            parts = line.split()
            if len(parts) >= 8:
                table_data.append({
                    'second': int(parts[0]),
                    'current_ops': int(parts[1]),
                    'started': int(parts[2]),
                    'finished': int(parts[3]),
                    'avg_mb_s': float(parts[4]),
                    'cur_mb_s': float(parts[5]),
                    'last_lat_s': float(parts[6]),
                    'avg_lat_s': float(parts[7])
                })
    
    result['table_data'] = table_data
    
    return result

def export_to_csv(parsed_data, csv_filename):
    """Export parsed data to CSV format"""
    
    with open(csv_filename, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        
        # Write header
        writer.writerow(['RADOS Bench Test Results'])
        writer.writerow([''])
        
        # Write summary metrics
        writer.writerow(['Summary Metrics', 'Value', 'Unit'])
        
        # Define metric mappings with units
        metric_mappings = [
            ('Total time run', 'Total time run', 'seconds'),
            ('Total writes made', 'Total writes made', 'operations'),
            ('Write size', 'Write size', 'bytes'),
            ('Object size', 'Object size', 'bytes'),
            ('Bandwidth (MB/sec)', 'Bandwidth (MB/sec)', 'MB/s'),
            ('Stddev Bandwidth', 'Stddev Bandwidth', 'MB/s'),
            ('Max bandwidth (MB/sec)', 'Max bandwidth (MB/sec)', 'MB/s'),
            ('Min bandwidth (MB/sec)', 'Min bandwidth (MB/sec)', 'MB/s'),
            ('Average IOPS', 'Average IOPS', 'IOPS'),
            ('Stddev IOPS', 'Stddev IOPS', 'IOPS'),
            ('Max IOPS', 'Max IOPS', 'IOPS'),
            ('Min IOPS', 'Min IOPS', 'IOPS'),
            ('Average Latency(s)', 'Average Latency(s)', 'seconds'),
            ('Stddev Latency(s)', 'Stddev Latency(s)', 'seconds'),
            ('Max latency(s)', 'Max latency(s)', 'seconds'),
            ('Min latency(s)', 'Min latency(s)', 'seconds')
        ]
        
        for display_name, key, unit in metric_mappings:
            if key in parsed_data:
                writer.writerow([display_name, parsed_data[key], unit])
        
        writer.writerow([''])
        
        # Write table data if available
        if 'table_data' in parsed_data and parsed_data['table_data']:
            writer.writerow(['Real-time Performance Data'])
            writer.writerow(['Second', 'Current Ops', 'Started', 'Finished', 'Avg MB/s', 'Cur MB/s', 'Last Latency(s)', 'Avg Latency(s)'])
            
            for row in parsed_data['table_data']:
                writer.writerow([
                    row['second'],
                    row['current_ops'],
                    row['started'],
                    row['finished'],
                    row['avg_mb_s'],
                    row['cur_mb_s'],
                    row['last_lat_s'],
                    row['avg_lat_s']
                ])
        
        writer.writerow([''])
        
        # Write all raw data
        writer.writerow(['All Raw Data'])
        writer.writerow(['Key', 'Value'])
        for key, value in parsed_data.items():
            if key != 'table_data':
                writer.writerow([key, value])

def main():
    parser = argparse.ArgumentParser(description='Parse rados bench output and convert to CSV')
    parser.add_argument('input', help='Input text file containing rados bench output')
    parser.add_argument('-o', '--output', help='Output CSV file (default: input_file.csv)')
    
    args = parser.parse_args()
    
    # Read input file
    try:
        with open(args.input, 'r') as f:
            output_text = f.read()
    except FileNotFoundError:
        print(f"Error: File {args.input} not found")
        sys.exit(1)
    except Exception as e:
        print(f"Error reading {args.input}: {e}")
        sys.exit(1)
    
    # Parse the output
    parsed_data = parse_rados_bench_output(output_text)
    if parsed_data is None:
        sys.exit(1)
    
    # Generate output filename
    if args.output:
        csv_filename = args.output
    else:
        csv_filename = args.input.replace('.txt', '.csv').replace('.log', '.csv') + '.csv'
    
    # Export to CSV
    try:
        export_to_csv(parsed_data, csv_filename)
        print(f"Successfully converted {args.input} to {csv_filename}")
    except Exception as e:
        print(f"Error writing CSV file: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
