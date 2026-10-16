#!/usr/bin/env python3
"""
Fetch wallet and transactions from the configured API for quick local testing.
Usage:
  python3 scripts/fetch_wallet.py --base https://rijhub.com --token <JWT> [--page 1 --limit 25]

This script is intentionally minimal and uses only the standard library.
"""
import argparse, sys, json, urllib.request


def get(url, token):
    req = urllib.request.Request(url)
    req.add_header('Authorization', f'Bearer {token}')
    req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read().decode('utf-8')
            return resp.getcode(), json.loads(data)
    except urllib.error.HTTPError as e:
        try:
            body = e.read().decode('utf-8')
            return e.code, json.loads(body)
        except Exception:
            return e.code, { 'error': str(e) }
    except Exception as e:
        return None, { 'error': str(e) }


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--base', required=True, help='API base URL')
    p.add_argument('--token', required=True, help='Bearer token JWT')
    p.add_argument('--page', type=int, default=1)
    p.add_argument('--limit', type=int, default=25)
    args = p.parse_args()

    base = args.base.rstrip('/')
    token = args.token
    page = args.page
    limit = args.limit

    print('Fetching wallet...')
    code, wallet = get(f'{base}/api/wallet', token)
    print('Wallet status:', code)
    print(json.dumps(wallet, indent=2))

    print('\nFetching payout details...')
    code, pd = get(f'{base}/api/wallet/payout-details', token)
    print('Payout status:', code)
    print(json.dumps(pd, indent=2))

    print('\nFetching transactions...')
    code, tx = get(f'{base}/api/transactions?page={page}&limit={limit}', token)
    print('Transactions status:', code)
    print(json.dumps(tx, indent=2))


if __name__ == '__main__':
    main()
