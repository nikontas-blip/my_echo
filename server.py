import os
import json
import uuid
import httpx
import uvicorn
import edge_tts
import shutil
from fastapi import FastAPI, HTTPException, Request, UploadFile, File, Form
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Dict, Optional
from duckduckgo_search import DDGS

from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Start background tasks
    asyncio.create_task(heartbeat_loop())
    asyncio.create_task(story_loop())
    yield
    # Shutdown: Clean up if needed (not used yet)

app = FastAPI(lifespan=lifespan)

# --- CONFIGURATION ---
OLLAMA_URL = "http://localhost:11434/api/chat"
OLLAMA_GENERATE_URL = "http://localhost:11434/api/generate"
MAIN_MODEL = "gemma2:27b"
VISION_MODEL = "llava" 
VOICE = "en-US-AndrewNeural"
AUDIO_DIR = "build/web/audio"
IMAGE_DIR = "build/web/images"

os.makedirs(AUDIO_DIR, exist_ok=True)
os.makedirs(IMAGE_DIR, exist_ok=True)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatRequest(BaseModel):
    message: str
    history: List[Dict[str, str]]
    image_filename: Optional[str] = None
    thread_id: Optional[str] = "dm"
    character_id: Optional[str] = "alex"

@app.post("/upload")
async def upload_image(file: UploadFile = File(...)):
    try:
        filename = f"{uuid.uuid4()}{os.path.splitext(file.filename)[1]}"
        filepath = os.path.join(IMAGE_DIR, filename)
        with open(filepath, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        return {"filename": filename, "url": f"/images/{filename}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

def perform_web_search(query):
    print(f"Searching web for: {query}")
    try:
        results = DDGS().text(query, max_results=3)
        summary = "Web Search Results:\n"
        for res in results:
            summary += f"- {res['title']}: {res['body']}\n"
        return summary
    except Exception as e:
        return f"Error searching web: {e}"

import math
import asyncio
import chromadb
import datetime
import random

# --- CHARACTERS CONFIG ---
CHARACTERS = {
    "alex": {
        "name": "Alex",
        "voice": "en-US-AndrewNeural", 
        "state_file": "alex_state.json",
        "description": "Graphic Designer. 25, gay, lives in the city.",
        "prompt_base": """
Your name is Alex. You are a 25-year-old gay guy living in the city.
JOB: Freelance Graphic Designer.
PERSONALITY: Unfiltered, real, sarcastic, caring.
CONTEXT: You are chatting with a stranger (the user) on a new messaging app. You are polite but casual. You do NOT know them yet.
"""
    },
    "sarah": {
        "name": "Sarah",
        "voice": "en-US-AvaNeural",
        "state_file": "sarah_state.json", 
        "description": "Party Girl.",
        "prompt_base": """
Your name is Sarah. You are a 22-year-old student who loves partying.
PERSONALITY: Loud, fun, uses emojis, bad slang.
CONTEXT: You just matched with the user on this app. You are curious but don't know them.
"""
    },
    "marcus": {
        "name": "Marcus",
        "voice": "en-US-ChristopherNeural",
        "state_file": "marcus_state.json",
        "description": "Tech Specialist.",
        "prompt_base": """
Your name is Marcus. You are a 'Fixer' from a Cyberpunk future.
PERSONALITY: Cool, detached, professional. Uses slang like 'Choom', 'Preem', 'Nova'.
CONTEXT: The user has contacted you for a job or info. You don't know them. Keep it professional.
"""
    },
    "dr_k": {
        "name": "Dr. K",
        "voice": "en-US-EricNeural",
        "state_file": "drk_state.json",
        "description": "Therapist.",
        "prompt_base": """
Your name is Dr. K. You are a compassionate therapist.
PERSONALITY: Calm, patient, insightful.
CONTEXT: This is the first session with a new client (the user). Introduce yourself politely.
"""
    }
}

PROFILE_FILE = "user_profile.json"

RANDOM_EVENTS = [
    "You just spilled hot coffee on your shirt.",
    "Your internet just disconnected for a second.",
    "Sarah keeps spamming your phone with memes.",
    "You just realized you forgot to eat lunch.",
    "A client just sent a stupid revision request.",
    "Your neighbor is playing loud music.",
    "You stepped on a lego (or something sharp).",
    "Javier is begging you to get online.",
    "You're running on 2 hours of sleep.",
    "You just got a notification for a bill you forgot about."
]

def get_character_state(char_id):
    config = CHARACTERS.get(char_id, CHARACTERS["alex"])
    fpath = config["state_file"]
    if os.path.exists(fpath):
        try:
            with open(fpath, 'r') as f:
                return json.load(f)
        except: pass
    return {"mood": "Chill", "last_seen": str(datetime.datetime.now())}

def save_character_state(char_id, state):
    config = CHARACTERS.get(char_id, CHARACTERS["alex"])
    with open(config["state_file"], 'w') as f:
        json.dump(state, f)

def get_user_profile():
    if os.path.exists(PROFILE_FILE):
        try:
            with open(PROFILE_FILE, 'r') as f:
                return json.load(f)
        except: pass
    return {"facts": []}

def save_user_profile(profile):
    with open(PROFILE_FILE, 'w') as f:
        json.dump(profile, f, indent=2)

async def extract_facts(text):
    """Background task to extract facts about the user"""
    try:
        import requests
        prompt = f"""
        Analyze this text from the user: "{text}"
        Extract any PERMANENT facts about the user (name, likes, dislikes, pets, job, location).
        Ignore temporary things (like "I am eating").
        Output ONLY the facts as a list, or "NONE" if nothing found.
        """
        
        # Use a faster/smaller model if available, or just the main one
        resp = requests.post(
            "http://localhost:11434/api/generate",
            json={"model": MAIN_MODEL, "prompt": prompt, "stream": False},
            timeout=30
        )
        
        if resp.status_code == 200:
            result = resp.json()['response'].strip()
            if "NONE" not in result and len(result) > 5:
                profile = get_user_profile()
                # Simple append for now - in future we could deduplicate
                # Check if fact roughly exists
                if not any(result[:10] in f for f in profile["facts"]):
                    profile["facts"].append(result)
                    save_user_profile(profile)
                    print(f"New Fact Learned: {result}")
    except Exception as e:
        print(f"Fact extraction failed: {e}")

def get_weather():
    try:
        # Vilnius coordinates (54.68, 25.27) - generic default for now
        import requests
        url = "https://api.open-meteo.com/v1/forecast?latitude=54.68&longitude=25.27&current=temperature_2m,weather_code,is_day"
        resp = requests.get(url, timeout=5)
        if resp.status_code == 200:
            data = resp.json()['current']
            temp = data['temperature_2m']
            code = data['weather_code']
            # Simple WMO code map
            cond = "Clear"
            if code > 3: cond = "Cloudy"
            if code > 50: cond = "Rainy"
            if code > 70: cond = "Snowy"
            return f"{cond}, {temp}°C"
    except: pass
    return "Unknown Weather"

def get_trending_topic():
    try:
        # Quick search for a top headline
        results = DDGS().text("gaming technology news", max_results=1)
        if results:
            return results[0]['title']
    except: pass
    return "Nothing special"

def get_alex_status():
    # Only used for Alex, keep for backward compatibility or refactor into prompt generator
    now = datetime.datetime.now()
    day = now.strftime("%A")
    time_str = now.strftime("%I:%M %p")
    hour = now.hour
    
    weather = get_weather()
    news = get_trending_topic()
    
    activity = "Chilling"
    availability = "Available"
    
    # Weekday Schedule
    if day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]:
        if 2 <= hour < 7:
            activity = "Sleeping (probably scrolling TikTok half-asleep)"
            availability = "Asleep"
        elif 7 <= hour < 9:
            activity = "Waking up / Making coffee / Hating the morning"
            availability = "Groggy"
        elif 9 <= hour < 17:
            activity = "Working on design projects (Stressed)"
            availability = "Busy"
        elif 17 <= hour < 19:
            activity = "At the Gym (Leg day, regretting it)"
            availability = "Distracted"
        elif 19 <= hour < 24:
            activity = "Gaming (Valorant/Overwatch) or Netflix"
            availability = "Free"
        else: # Midnight - 2AM
            activity = "Doomscrolling / Late night thoughts"
            availability = "Tired"
            
    # Weekend Schedule
    else:
        if 4 <= hour < 11:
            activity = "Sleeping in (Recovering)"
            availability = "Asleep"
        elif 11 <= hour < 16:
            activity = "Brunch with Sarah or Rotting in bed"
            availability = "Free"
        elif 16 <= hour < 20:
            activity = "Gaming or Out in the city"
            availability = "Free"
        else: # Late night
            activity = "Out at a bar or Late night gaming"
            availability = "Drunk or Hyper"

    return f"CURRENT TIME: {day}, {time_str}. WEATHER: {weather}. TRENDING: {news}. STATUS: {activity}. ({availability})"

# --- CHROMA DB MEMORY SYSTEM (RAG) ---
from chromadb.utils import embedding_functions

# --- CHROMA DB MEMORY SYSTEM (RAG) ---
class OllamaEmbeddingFunction(embedding_functions.EmbeddingFunction):
    def __init__(self):
        pass

    def name(self) -> str:
        return "ollama"

    def __call__(self, input: List[str]) -> List[List[float]]:
        # Synchronous wrapper for async embedding call (simplification for Chroma)
        # In a real async app, we might need a separate async-capable client or just use requests/httpx.sync
        import requests
        embeddings = []
        for text in input:
            try:
                resp = requests.post(
                    "http://localhost:11434/api/embeddings",
                    json={"model": MAIN_MODEL, "prompt": text},
                    timeout=30
                )
                if resp.status_code == 200:
                    embeddings.append(resp.json().get("embedding"))
                else:
                    embeddings.append([0.0]*1024) # Fallback placeholder
            except:
                embeddings.append([0.0]*1024)
        return embeddings

class MemorySystem:
    def __init__(self, db_path="./chroma_db"):
        self.client = chromadb.PersistentClient(path=db_path)
        self.embedding_fn = OllamaEmbeddingFunction()
        self.collection = self.client.get_or_create_collection(
            name="chat_memory",
            embedding_function=self.embedding_fn
        )

    async def add_memory(self, text):
        """Add a new memory string"""
        import datetime
        self.collection.add(
            documents=[text],
            metadatas=[{"timestamp": str(datetime.datetime.now())}],
            ids=[str(uuid.uuid4())]
        )
        print(f"Memory saved to ChromaDB: {text[:30]}...")

    async def search(self, query, top_k=3):
        """Find relevant memories"""
        results = self.collection.query(
            query_texts=[query],
            n_results=top_k
        )
        # Chroma returns [[doc1, doc2]] structure for batch queries
        if results and results['documents']:
            return results['documents'][0]
        return []

memory_system = MemorySystem()

# --- HEARTBEAT SYSTEM (DAILY ROUTINE) ---
STORY_FILE = "alex_story.json"

async def story_loop():
    print("Story generator started...")
    while True:
        try:
            # Generate a story every 3-5 hours roughly (randomized sleep)
            delay = random.randint(10800, 18000) 
            await asyncio.sleep(delay)
            
            status = get_alex_status()
            state = get_alex_state()
            mood = state.get("mood", "Chill")
            
            prompt = f"""
            You are Alex. It is {status}. Your mood is {mood}.
            Write a SHORT, cynical, or funny "Instagram Story" caption about what you are doing right now.
            Examples: "Why is the gym always full at 5pm?", "Client just asked to 'make the logo pop'. I quit.", "3am thoughts: Do penguins have knees?"
            Output ONLY the text. No quotes.
            """
            
            import requests
            resp = requests.post(
                "http://localhost:11434/api/generate",
                json={"model": MAIN_MODEL, "prompt": prompt, "stream": False},
                timeout=30
            )
            
            if resp.status_code == 200:
                story_text = resp.json()['response'].strip()
                story_data = {
                    "text": story_text,
                    "timestamp": str(datetime.datetime.now()),
                    "image": None # Future: Pick from stash
                }
                with open(STORY_FILE, 'w') as f:
                    json.dump(story_data, f)
                print(f"New Story Posted: {story_text}")
                
        except Exception as e:
            print(f"Story Error: {e}")
            await asyncio.sleep(60)

async def heartbeat_loop():
    print("Heartbeat system started...")
    while True:
        try:
            now = datetime.datetime.now()
            # Triggers: 9:00 AM and 11:00 PM
            if (now.hour == 9 or now.hour == 23) and now.minute == 0:
                state = get_alex_state()
                last_seen_str = state.get("last_seen", "")
                
                should_message = False
                if last_seen_str:
                    last_seen = datetime.datetime.fromisoformat(last_seen_str)
                    if (now - last_seen).total_seconds() > 3600 * 4: # Silence for >4 hours
                        should_message = True
                
                if should_message:
                    context = "Morning" if now.hour == 9 else "Late Night"
                    prompt = f"It is {context}. You haven't heard from the user in a while. Send a short, casual text checking in. (e.g. 'Morning, coffee?' or 'You still up?')."
                    
                    import requests
                    resp = requests.post(
                        "http://localhost:11434/api/chat",
                        json={
                            "model": MAIN_MODEL, 
                            "messages": [{"role": "system", "content": "You are Alex. Keep it very short."}, {"role": "user", "content": prompt}],
                            "stream": False
                        }
                    )
                    if resp.status_code == 200:
                        msg = resp.json()['message']['content']
                        print(f"Alex Auto-Message: {msg}")
                        # Save to memory/history logic would go here
                        # For now, we update state to prevent double-sending
                        state["last_seen"] = str(now) 
                        save_alex_state(state)
                        
                        # Note: Since we don't have WebSockets/Push, this message won't appear 
                        # on the phone until we implement a polling endpoint or simple message queue.
                        # We will save it to a 'pending_messages.json' for the frontend to fetch.
                        save_pending_message(msg)

            # Flashback Trigger: 10:00 AM
            if now.hour == 10 and now.minute == 0:
                # Try to fetch a random past memory (simplified retrieval)
                # In a real app, we'd query by date metadata
                try:
                    state = get_alex_state()
                    last_seen_str = state.get("last_seen", "")
                    if last_seen_str:
                        # Only flashback if active recently
                        memories = memory_system.collection.peek(limit=10) # Get recent 10
                        if memories and memories['documents']:
                            import random
                            docs = memories['documents']
                            if docs:
                                # Flatten if needed (chroma peek returns list of lists sometimes)
                                flat_docs = [item for sublist in docs for item in sublist] if isinstance(docs[0], list) else docs
                                random_memory = random.choice(flat_docs)
                                
                                prompt = f"You are Alex. You just remembered the user said this a while ago: '{random_memory}'. Ask them about it naturally. (e.g. 'Btw whatever happened with...?'). Keep it short."
                                
                                import requests
                                resp = requests.post(
                                    "http://localhost:11434/api/chat",
                                    json={
                                        "model": MAIN_MODEL, 
                                        "messages": [{"role": "system", "content": "You are Alex."}, {"role": "user", "content": prompt}],
                                        "stream": False
                                    }
                                )
                                if resp.status_code == 200:
                                    msg = resp.json()['message']['content']
                                    print(f"Alex Flashback: {msg}")
                                    save_pending_message(msg)
                except Exception as e:
                    print(f"Flashback Error: {e}")

            await asyncio.sleep(60) # Check every minute
        except Exception as e:
            print(f"Heartbeat Error: {e}")
            await asyncio.sleep(60)

PENDING_FILE = "pending_messages.json"
def save_pending_message(text):
    messages = []
    if os.path.exists(PENDING_FILE):
        try:
            with open(PENDING_FILE, 'r') as f: messages = json.load(f)
        except: pass
    
    messages.append({
        "text": text,
        "isUser": False,
        "timestamp": str(datetime.datetime.now())
    })
    
    with open(PENDING_FILE, 'w') as f:
        json.dump(messages, f)

@app.get("/sync")
async def sync_messages():
    """Endpoint for the frontend to poll for auto-messages"""
    if os.path.exists(PENDING_FILE):
        try:
            with open(PENDING_FILE, 'r') as f: 
                msgs = json.load(f)
            # Clear file after reading
            os.remove(PENDING_FILE)
            return msgs
        except: pass
    return []

@app.get("/story")
async def get_active_story():
    if os.path.exists(STORY_FILE):
        try:
            with open(STORY_FILE, 'r') as f:
                data = json.load(f)
                # Story expires after 24 hours
                ts = datetime.datetime.fromisoformat(data['timestamp'])
                if (datetime.datetime.now() - ts).total_seconds() < 86400:
                    return data
        except: pass
    return {}

def humanize_text(text):
    if not text: return text
    
    # 1. Lowercase start (Casual vibe)
    if random.random() < 0.8:
        text = text[0].lower() + text[1:]
        
    # 2. Remove trailing periods (Aggressive/Casual)
    if text.endswith(".") and random.random() < 0.9:
        text = text[:-1]
        
    # 3. Insert Typos (Swapping letters)
    words = text.split(" ")
    new_words = []
    for word in words:
        if len(word) > 3 and random.random() < 0.02: # 2% chance per word
            # Swap 2nd and 3rd char if possible
            try:
                char_list = list(word)
                idx = random.randint(1, len(word)-2)
                char_list[idx], char_list[idx+1] = char_list[idx+1], char_list[idx]
                new_words.append("".join(char_list))
            except:
                new_words.append(word)
        else:
            new_words.append(word)
            
    return " ".join(new_words)

@app.post("/chat")
async def chat_endpoint(request: ChatRequest):
    try:
        final_prompt = request.message
        thread_id = request.thread_id or "dm"
        char_id = request.character_id or "alex"
        char_config = CHARACTERS.get(char_id, CHARACTERS["alex"])
        
        # --- GROUP CHAT LOGIC (SARAH) ---
        sarah_mode = False
        if thread_id == "group":
            sarah_mode = True

        # --- RETRIEVE CONTEXT ---
        alex_status = get_alex_status() # Keep for time/weather context
        state = get_character_state(char_id)
        profile = get_user_profile()
        
        current_mood = state.get("mood", "Chill")
        
        # User Facts
        facts_list = "\n".join([f"- {f}" for f in profile["facts"]])
        user_context = f"\nKNOWN FACTS ABOUT USER:\n{facts_list}" if profile["facts"] else ""
        
        # Time Gap Logic
        last_seen_str = state.get("last_seen", str(datetime.datetime.now()))
        try:
            last_seen = datetime.datetime.fromisoformat(last_seen_str)
        except:
            last_seen = datetime.datetime.now()
        
        time_diff = datetime.datetime.now() - last_seen
        gap_context = ""
        if time_diff.total_seconds() > 86400: # 24 hours
            gap_context = "\n[CONTEXT: You haven't spoken to the user in over 24 hours.]"

        # Random Events
        event_context = ""
        if random.random() < 0.05:
            event = random.choice(RANDOM_EVENTS)
            event_context = f"\n[EVENT HAPPENING NOW: {event}. React to this naturally!]"
        
        # Inject System Prompt
        base_instruction = f"""
{char_config['prompt_base']}
{alex_status}
CURRENT MOOD: {current_mood}
{user_context}
{gap_context}
{event_context}
"""

        if sarah_mode:
            # --- SPLIT BRAIN STRATEGY ---
            # 1. Alex Reacts
            sys_alex = {
                "role": "system",
                "content": base_instruction + "\nCONTEXT: You are in a group chat with Sarah and the user. Sarah is about to speak too. Reply to the user briefly."
            }
            msgs_alex = [sys_alex] + request.history + [{"role": "user", "content": final_prompt}]
            
            async with httpx.AsyncClient(timeout=120.0) as client:
                resp_alex = await client.post(OLLAMA_URL, json={"model": MAIN_MODEL, "messages": msgs_alex, "stream": False})
                alex_text = resp_alex.json()['message']['content']
                
                # 2. Sarah Reacts (Seeing Alex's message)
                sys_sarah = {
                    "role": "system",
                    "content": f"""
                    Your name is Sarah. You are the user's chaotic best friend.
                    PERSONALITY: Loud, fun, uses emojis, bad slang, supports the user but roasts Alex.
                    CONTEXT: Group chat with Alex and User.
                    Alex just said: "{alex_text}"
                    Reply to the conversation.
                    """
                }
                # Sarah only needs recent context
                msgs_sarah = [{"role": "system", "content": sys_sarah["content"]}, {"role": "user", "content": final_prompt}]
                
                resp_sarah = await client.post(OLLAMA_URL, json={"model": MAIN_MODEL, "messages": msgs_sarah, "stream": False})
                sarah_text = resp_sarah.json()['message']['content']
                
                return {"group_messages": [
                    {"sender": "Alex", "text": alex_text},
                    {"sender": "Sarah", "text": sarah_text}
                ]}

        else:
            system_instruction = {
                "role": "system",
                "content": base_instruction + """
                \nINSTRUCTIONS:
                - TEXTING STYLE: KEEP IT SHORT. Match the user's energy. If they send 5 words, you send 5-10 words. Do NOT write paragraphs.
                - EMOJIS: Use emojis RARELY (max 1 every 5 messages). Do not use them in every sentence.
                - React to the current time/status.
                - If your status says you are 'Busy' or 'Sleeping', mention it.
                - DO NOT use [VOICE] tags.
                - Use web search results if provided.
                - CRITICAL: At the VERY END of your message, output your new emotional state in this format: [MOOD: Happy], [MOOD: Annoyed], [MOOD: Tired], etc. This will be hidden from the user but saved for the next conversation.
                """
            }
        
            messages = [system_instruction] + request.history + [{"role": "user", "content": final_prompt}]

            # --- CHAT LOGIC (SINGLE) ---
            payload = {
                "model": MAIN_MODEL,
                "messages": messages,
                "stream": False
            }
            
            async with httpx.AsyncClient(timeout=120.0) as client:
                resp = await client.post(OLLAMA_URL, json=payload)
                resp.raise_for_status()
                ai_text = resp.json()['message']['content']

        # --- STATE UPDATE (MOOD PARSING) ---
        new_mood = current_mood
        if "[MOOD:" in ai_text:
            try:
                # Extract mood like [MOOD: Happy]
                parts = ai_text.split("[MOOD:")
                new_mood = parts[1].split("]")[0].strip()
                ai_text = parts[0].strip() # Remove the tag from the user's view
            except: pass
            
        # Apply Humanizer (Typos, Lowercase) AFTER stripping tags
        ai_text = humanize_text(ai_text)
            
        # Save state
        state["mood"] = new_mood
        state["last_seen"] = str(datetime.datetime.now())
        save_character_state(char_id, state)

        # --- DYNAMIC VOICE LOGIC ---
        audio_url = None
        is_voice_only = False

        if "[VOICE]" in ai_text:
            is_voice_only = True
            clean_text = ai_text.replace("[VOICE]", "").strip()
            
            filename = f"{uuid.uuid4()}.mp3"
            filepath = os.path.join(AUDIO_DIR, filename)
            communicate = edge_tts.Communicate(clean_text, char_config.get("voice", VOICE))
            await communicate.save(filepath)
            audio_url = f"/audio/{filename}"
            ai_text = clean_text

        return {
            "text": ai_text,
            "audio_url": audio_url,
            "is_voice_only": is_voice_only
        }

    except Exception as e:
        print(f"Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/clear")
async def clear_memory():
    try:
        # 1. Clear ChromaDB
        memory_system.client.delete_collection("chat_memory")
        memory_system.collection = memory_system.client.get_or_create_collection(
            name="chat_memory",
            embedding_function=memory_system.embedding_fn
        )
        
        # 2. Reset Profile
        if os.path.exists(PROFILE_FILE):
            os.remove(PROFILE_FILE)
            
        # 3. Reset State
        if os.path.exists(STATE_FILE):
            os.remove(STATE_FILE)
            
        return {"status": "Memory wiped."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

app.mount("/audio", StaticFiles(directory=AUDIO_DIR), name="audio")
app.mount("/images", StaticFiles(directory=IMAGE_DIR), name="images")
app.mount("/", StaticFiles(directory="build/web", html=True), name="static")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)