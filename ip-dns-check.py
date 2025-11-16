#!/usr/bin/env python3
"""
DNS Lookup Tool
Performs nslookup on hostnames and saves results to a file.
"""

import socket
import argparse
import sys
from datetime import datetime

try:
    import dns.resolver
    DNS_AVAILABLE = True
except ImportError:
    DNS_AVAILABLE = False


def perform_dns_lookup(hostname, dns_server=None):
    """
    Perform DNS lookup for a given hostname.
    
    Args:
        hostname (str): The hostname to lookup
        dns_server (str): Optional custom DNS server IP address
        
    Returns:
        tuple: (hostname, ip_address, success)
    """
    try:
        if dns_server and DNS_AVAILABLE:
            # Use custom DNS server with dnspython
            resolver = dns.resolver.Resolver()
            resolver.nameservers = [dns_server]
            answers = resolver.resolve(hostname, 'A')
            ip_address = str(answers[0])
            return (hostname, ip_address, True)
        elif dns_server and not DNS_AVAILABLE:
            return (hostname, "Error: dnspython not installed (required for custom DNS)", False)
        else:
            # Use system default DNS
            ip_address = socket.gethostbyname(hostname)
            return (hostname, ip_address, True)
    except dns.resolver.NXDOMAIN:
        return (hostname, "Error: Domain does not exist", False)
    except dns.resolver.NoAnswer:
        return (hostname, "Error: No A record found", False)
    except dns.resolver.Timeout:
        return (hostname, "Error: DNS query timeout", False)
    except socket.gaierror as e:
        return (hostname, f"Error: {str(e)}", False)
    except Exception as e:
        return (hostname, f"Unexpected error: {str(e)}", False)


def read_hostnames(input_source):
    """
    Read hostnames from file or command line argument.
    
    Args:
        input_source (str): Either a filename or a single hostname
        
    Returns:
        list: List of hostnames to lookup
    """
    hostnames = []
    
    # Try to read as a file first
    try:
        with open(input_source, 'r') as f:
            hostnames = [line.strip() for line in f if line.strip()]
    except FileNotFoundError:
        # If file doesn't exist, treat as a single hostname
        hostnames = [input_source]
    except Exception as e:
        print(f"Error reading input: {e}", file=sys.stderr)
        sys.exit(1)
    
    return hostnames


def write_results(results, output_file, verbose=False, dns_server=None):
    """
    Write DNS lookup results to a file.
    
    Args:
        results (list): List of tuples (hostname, ip_address, success)
        output_file (str): Output filename
        verbose (bool): Whether to print results to console as well
        dns_server (str): Custom DNS server used (if any)
    """
    try:
        with open(output_file, 'w') as f:
            # Write header
            f.write(f"DNS Lookup Results - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            if dns_server:
                f.write(f"DNS Server: {dns_server}\n")
            else:
                f.write("DNS Server: System Default\n")
            f.write("=" * 70 + "\n\n")
            
            # Write results
            for hostname, ip_address, success in results:
                line = f"{hostname} / {ip_address}\n"
                f.write(line)
                
                if verbose:
                    print(line.strip())
            
            # Write summary
            success_count = sum(1 for _, _, success in results if success)
            f.write("\n" + "=" * 70 + "\n")
            f.write(f"Total lookups: {len(results)}\n")
            f.write(f"Successful: {success_count}\n")
            f.write(f"Failed: {len(results) - success_count}\n")
        
        print(f"\nResults written to: {output_file}")
        
    except Exception as e:
        print(f"Error writing to output file: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description='Perform DNS lookups and save results to a file',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  %(prog)s -i google.com -o results.txt
  %(prog)s -i hostnames.txt -o results.txt
  %(prog)s -i example.com -o output.txt -v
  %(prog)s -i hostnames.txt -o results.txt -d 8.8.8.8
  %(prog)s -i example.com -o output.txt -d 1.1.1.1 -v
        '''
    )
    
    parser.add_argument(
        '-i', '--input',
        required=True,
        help='Input hostname or file containing hostnames (one per line)'
    )
    
    parser.add_argument(
        '-o', '--output',
        required=True,
        help='Output file to save results'
    )
    
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Print results to console as well as file'
    )
    
    parser.add_argument(
        '-d', '--dns',
        metavar='DNS_IP',
        help='Custom DNS server IP address (e.g., 8.8.8.8, 1.1.1.1)'
    )
    
    args = parser.parse_args()
    
    # Validate DNS server IP if provided
    if args.dns:
        try:
            socket.inet_aton(args.dns)
        except socket.error:
            print(f"Error: Invalid DNS server IP address: {args.dns}", file=sys.stderr)
            sys.exit(1)
        
        if not DNS_AVAILABLE:
            print("Warning: dnspython library not installed.", file=sys.stderr)
            print("Install it with: pip install dnspython", file=sys.stderr)
            print("Falling back to system DNS...\n", file=sys.stderr)
    
    # Read hostnames
    print(f"Reading hostnames from: {args.input}")
    hostnames = read_hostnames(args.input)
    
    if not hostnames:
        print("No hostnames found to lookup", file=sys.stderr)
        sys.exit(1)
    
    dns_info = f" using DNS server {args.dns}" if args.dns else ""
    print(f"Performing DNS lookups for {len(hostnames)} hostname(s){dns_info}...\n")
    
    # Perform lookups
    results = []
    for hostname in hostnames:
        result = perform_dns_lookup(hostname, args.dns)
        results.append(result)
        
        # Show progress
        status = "✓" if result[2] else "✗"
        print(f"{status} {hostname}")
    
    # Write results
    write_results(results, args.output, args.verbose, args.dns)
    
    # Exit with appropriate code
    failed_count = sum(1 for _, _, success in results if not success)
    sys.exit(0 if failed_count == 0 else 1)


if __name__ == "__main__":
    main()
