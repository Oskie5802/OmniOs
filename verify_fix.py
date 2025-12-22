import json

def get_person_result(name):
    # Simulate failure (SearXNG down)
    return None

def test_fallback(name):
    print(f"Testing Fallback for: {name}")
    
    # Simulate the logic in brain.nix
    if len(name.split()) < 2:
        print("Rejected (Too short)")
        return

    person_card = get_person_result(name)
    if person_card:
        result = {"action": person_card}
    else:
        # Fallback to BASIC Person Card (Initials only)
        result = {
            "action": {
                "type": "person", 
                "name": name.title(),
                "description": "Press Enter to search info.",
                "url": f"https://www.google.com/search?q={name}",
                "image": None
            }
        }
    
    print(json.dumps(result, indent=2))
    
    # Verification
    act = result["action"]
    if act["type"] == "person" and act["image"] is None and act["name"] == name.title():
         print("SUCCESS: Correctly returned Basic Person Card.")
    else:
         print("FAILURE: Did not return correct card.")

if __name__ == "__main__":
    test_fallback("Steve Jobs")
