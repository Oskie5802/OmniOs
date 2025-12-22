import requests
import json

SEARXNG_URL = "http://127.0.0.1:8888/search"

def test_person_search(name):
    print(f"Testing search for: {name}")
    try:
        # Mimic brain.nix logic
        params = {'q': name, 'format': 'json', 'categories': 'general', 'language': 'en-US'}
        print(f"Requesting: {SEARXNG_URL} with params {params}")
        resp = requests.get(SEARXNG_URL, params=params, timeout=10.0)
        
        print(f"Status Code: {resp.status_code}")
        if resp.status_code == 200:
            data = resp.json()
            results = data.get('results', [])
            print(f"Found {len(results)} results")
            if results:
                first = results[0]
                print("First Result Item keys:", first.keys())
                print("First Result Title:", first.get('title'))
                print("First Result Content:", first.get('content'))
                print("First Result Snippet:", first.get('snippet'))
            else:
                print("No results found in 'results' list.")
        else:
            print(f"Error: {resp.text}")

    except Exception as e:
        print(f"Exception: {e}")

if __name__ == "__main__":
    test_person_search("Steve Jobs")
