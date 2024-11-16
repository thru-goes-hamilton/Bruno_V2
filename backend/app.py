import json
import shutil
import time
import os
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pathlib import Path
from langchain.embeddings import HuggingFaceEmbeddings
from langchain.vectorstores import Pinecone
from pinecone import ServerlessSpec
from dotenv import load_dotenv
from typing import Sequence
from langchain.chains import create_history_aware_retriever, create_retrieval_chain
from langchain.chains.combine_documents import create_stuff_documents_chain
from langchain_core.messages import AIMessage, BaseMessage, HumanMessage,AIMessageChunk,trim_messages
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph import START, StateGraph
from langgraph.graph.message import add_messages
from typing_extensions import Annotated, TypedDict
from langchain_groq import ChatGroq
from langchain.document_loaders import PyPDFLoader, Docx2txtLoader, TextLoader
from langchain.retrievers import EnsembleRetriever
from langchain_community.retrievers import BM25Retriever
from langchain.prompts import PromptTemplate
from typing import Sequence, Optional, List, Dict
from pydantic import BaseModel

# Load environment variables from .env file
load_dotenv()

app = FastAPI()

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins
    allow_credentials=True,
    allow_methods=["*"],  # Allows all methods
    allow_headers=["*"],  # Allows all headers
)

# Add state management class
class AppState:
    def __init__(self):
        self.langgraph_apps: Dict[str, StateGraph] = {}
        self.retrievers: Dict[str, EnsembleRetriever] = {}

# Initialize state
app.state.app_state = AppState()


UPLOAD_FOLDER = Path("uploaded_files")
UPLOAD_FOLDER.mkdir(exist_ok=True)

pinecone_apikey=os.getenv("PINECONE_API_KEY")
groq_apikey=os.getenv("GROQ_API_KEY")
pinecone_environment=os.getenv("PINECONE_ENVIRONMENT")

llm = ChatGroq(model="llama3-8b-8192",groq_api_key=groq_apikey,streaming=True)

embeddings = HuggingFaceEmbeddings()

from pinecone import Pinecone
pc = Pinecone(pinecone_apikey)
cloud = 'aws'
region = pinecone_environment
spec = ServerlessSpec(cloud=cloud, region=region)

class ChatRequest(BaseModel):
    message: str
    chat_history: List[Dict[str, str]] = []
    use_rag: bool = True

@app.post("/extract-and-vectorize/{session_id}")
async def extract_and_vectorize_route(session_id:str):
    try:
        
        # Your existing extraction and vectorization code...
        UPLOAD_FOLDER = Path("uploaded_files")
        session_folder = UPLOAD_FOLDER / session_id
        all_text = ""

        for file_path in session_folder.glob("*"):
            print(file_path)
            if file_path.suffix == ".pdf":
                loader = PyPDFLoader(str(file_path))
            elif file_path.suffix in [".doc", ".docx"]:
                loader = Docx2txtLoader(str(file_path))
            elif file_path.suffix == ".txt":
                loader = TextLoader(str(file_path))
            else:
                continue

            documents = loader.load()
            all_text += " ".join([doc.page_content for doc in documents])
        print("loaded docs")

        # Split text and process chunks...
        from langchain.text_splitter import RecursiveCharacterTextSplitter
        text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
        chunks = text_splitter.split_text(all_text)
        print(f"chunking done: {chunks[0]}")
        # Your existing chunk processing code...
        prompt_template = PromptTemplate(
            input_variables=["WHOLE_DOCUMENT", "CHUNK_CONTENT"],
            template=(
                "<document> {WHOLE_DOCUMENT} </document> "
                "Here is the chunk we want to situate within the whole document "
                "<chunk> {CHUNK_CONTENT} </chunk> "
                "Please give a short succinct context to situate this chunk within "
                "the overall document for the purposes of improving search retrieval "
                "of the chunk. Answer only with the succinct context and nothing else."
            )
        )
        
        processed_chunks = []
        for chunk in chunks:
            prompt = prompt_template.format(
                WHOLE_DOCUMENT=all_text,
                CHUNK_CONTENT=chunk
            )
            try:
                # Send to LLM if within token limit
                response = llm.invoke(prompt)
                processed_chunks.append(response.content)
            except Exception as e:
                print(f"Error processing chunk: {e}")
                processed_chunks=[]
                processed_chunks=chunks
                break
        

        # Create retrievers...
        bm25_retriever = BM25Retriever.from_texts(processed_chunks)
        bm25_retriever.k = 2

        index_name=session_id

        # First check if index already exists
        existing_indexes = pc.list_indexes()

        # If index doesn't exist, create it
        if index_name not in existing_indexes:

            print(f"Creating new index: {index_name}")
            start_time = time.time()
            pc.create_index(
                name=index_name,
                dimension=768,
                metric='cosine',
                spec=spec
            )

            print(f"Ran code for creating new index {index_name}")

            ready = False
            while not ready:
                try:
                    desc = pc.describe_index(index_name)
                    if desc[7]['ready']:
                        ready = True
                except pc.core.client.exceptions.NotFoundException:
                # NotFoundException means the index is created yet.
                    pass
                time.sleep(2)
            
            end_time = time.time()
            print(f"Index {index_name} ready after {end_time - start_time:.2f} seconds")


        from langchain.vectorstores import Pinecone
        vector_store = Pinecone.from_texts(processed_chunks, embeddings, index_name=index_name)
        pinecone_retriever = vector_store.as_retriever(search_kwargs={"k": 2})

        global_retriever = EnsembleRetriever(
            retrievers=[bm25_retriever, pinecone_retriever], weights=[0.5, 0.5]
        )
        print("retriever setup")
        # Setup prompts and chains... 

        ### Contextualize question ###
        contextualize_q_system_prompt = (
            "Given a chat history and the latest user question "
            "which might reference context in the chat history, "
            "formulate a standalone question which can be understood "
            "without the chat history. Do NOT answer the question, "
            "just reformulate it if needed and otherwise return it as is."
        )
        contextualize_q_prompt = ChatPromptTemplate.from_messages(
            [
                ("system", contextualize_q_system_prompt),
                MessagesPlaceholder("chat_history"),
                ("human", "{input}"),
            ]
        )

        ### Define system prompts for both modes ###
        rag_system_prompt = (
            "You are an assistant named Bruno(inspired from your creators pet dog) for question-answering tasks. "
            "Use the following pieces of retrieved context to answer "
            "the question. If the context is not sufficient to answer the question, mention that you are not answering from provided context and continue to answer the question ignoring the context. Ask for additional information that could have helped to answer at the end in one line. If the context is sufficient just answer the question."
            "\n\n"
            "{context}"
        )

        ### Create prompts for both modes ###
        rag_qa_prompt = ChatPromptTemplate.from_messages(
            [
                ("system", rag_system_prompt),
                MessagesPlaceholder("chat_history"),
                ("human", "{input}"),
            ]
        )

        history_aware_retriever = create_history_aware_retriever(
            llm, global_retriever, contextualize_q_prompt
        )

        rag_question_answer_chain = create_stuff_documents_chain(llm, rag_qa_prompt)
        rag_chain = create_retrieval_chain(history_aware_retriever, rag_question_answer_chain)
        
        print("chain setup")

        trimmer = trim_messages(
            max_tokens=65,
            strategy="last",
            token_counter=llm,
            include_system=True,
            allow_partial=False,
            start_on="human",
        )
        # Your State class and call_model function
        class State(TypedDict):
            input: str
            chat_history: Annotated[Sequence[BaseMessage], add_messages]
            context: str
            answer: str
            use_rag: bool

            @classmethod
            def initialize(cls):
                return cls(
                    input="",
                    chat_history=[],
                    context="",
                    answer="",
                    use_rag=False
                )

        async def call_model(state: State):
            accumulated_state = {
                "chat_history": [],
                "context": "",
                "answer": ""
            }
            last_content = ""  # Track last content to avoid duplicates
            trimmed_messages = trimmer.invoke(state["chat_history"])
            async for chunk in rag_chain.astream({**state, "chat_history": trimmed_messages}):
                # We only want the final answer after retrieval and processing
                # The history aware retriever output will be in a different format
                if ("answer" in chunk and isinstance(chunk["answer"], str) and 
                    "source_documents" in chunk):  # This indicates it's from the final RAG chain
                    new_content = chunk["answer"]
                    if new_content != last_content:  # Avoid duplicates
                        message_chunk = AIMessageChunk(content=new_content)
                        accumulated_state["answer"] += new_content
                        last_content = new_content
                        yield {"messages": [message_chunk]}

                if "context" in chunk:
                    accumulated_state["context"] = chunk["context"]
                    yield {"context":chunk["context"]}

            # Update chat history once at the end
            
            final_messages = [
                HumanMessage(content=state["input"]),
                AIMessage(content=accumulated_state["answer"])
            ]
                
            yield {
                "chat_history": final_messages,
                "answer": accumulated_state["answer"],
                "context": accumulated_state["context"]
            }

        # Create and store LangGraph app
        workflow = StateGraph(state_schema=State)
        workflow.add_edge(START, "model")
        workflow.add_node("model", call_model)
        workflow.set_entry_point("model")

        memory = MemorySaver()
        global_langgraph_app = workflow.compile(checkpointer=memory)

        app.state.app_state.retrievers[session_id] = global_retriever
        app.state.app_state.langgraph_apps[session_id] = global_langgraph_app

        print("langgraph setup")
        return JSONResponse(
            content={"message": "Extraction and vectorization completed successfully"},
            status_code=200
        )
    except Exception as e:
        print(f"Error is :{e}")
        raise HTTPException(
            status_code=500,
            detail=f"An error occurred during extraction and vectorization: {str(e)}"
        )

async def generate_stream(request: ChatRequest, session_id: str):
    global global_langgraph_app, global_retriever
    """Generator function for streaming responses"""
    if any(UPLOAD_FOLDER.glob("*")):
        # Check if session-specific folder has files
        session_folder = UPLOAD_FOLDER / session_id
        use_rag = any(session_folder.glob("*"))   # True if folder is not empty, False if empty
    else:
        use_rag  = False

        # Get session-specific langgraph app from state
    
    try:
        global_langgraph_app = app.state.app_state.langgraph_apps.get(session_id)
    except Exception as e:
        # Set the app state to None in case of an exception
        app.state.app_state.langgraph_apps[session_id] = None
        global_langgraph_app = app.state.app_state.langgraph_apps.get(session_id)
        # Optionally, log the error if needed
        print(f"Initializing langgraph_apps for no rag usecase with session_id {session_id}: {e}")


    if (global_langgraph_app is None) and (use_rag):
        raise HTTPException(
            status_code=500,
            detail="LangGraph app not initialized. Please run extraction first."
        )      

    if (global_langgraph_app is None) and (not use_rag):
        direct_system_prompt = (
            "You are an assistant named Bruno(inspired from your creators pet dog) for question-answering tasks. "
            "Answer only the question based on your general knowledge while maintaining a helpful and informative tone. "
        )

        direct_qa_prompt = ChatPromptTemplate.from_messages(
            [
                ("system", direct_system_prompt),
                MessagesPlaceholder("chat_history"),
                ("human", "{input}"),
            ]
        )
        direct_chain = direct_qa_prompt | llm

        trimmer = trim_messages(
            max_tokens=1000,
            strategy="last",
            token_counter=llm,
            include_system=True,
            allow_partial=False,
            start_on="human",
        )

        class State(TypedDict):
            input: str
            chat_history: Annotated[Sequence[BaseMessage], add_messages]
            context: str
            answer: str
            use_rag: bool
            
            @classmethod
            def initialize(cls):
                return cls(
                    input="",
                    chat_history=[],
                    context="",
                    answer="",
                    use_rag=False
                )


        async def call_model(state: State):                
            current_chat_history = list(state.get("chat_history", []))
            accumulated_answer = ""

            trimmed_messages = trimmer.invoke(state["chat_history"])

            async for chunk in direct_chain.astream({
                "input": state["input"],
                "chat_history": trimmed_messages
            }): 
                message_chunk = AIMessageChunk(content=chunk.content)
                yield {"messages": [message_chunk]}

            # Update chat history after completion
            current_chat_history.extend([
                HumanMessage(content=state["input"]),
                AIMessage(content=accumulated_answer)
            ])
            
            # Return final state update
            yield {
                "chat_history": current_chat_history,
                "answer": accumulated_answer,
                "context": state.get("context", "")
            }

        # Create and store LangGraph app
        workflow = StateGraph(state_schema=State)
        workflow.add_edge(START, "model")
        workflow.add_node("model", call_model)
        workflow.set_entry_point("model")

        memory = MemorySaver()
            # Get session-specific langgraph app from state
        app.state.app_state.langgraph_apps[session_id] = workflow.compile(checkpointer=memory)
        global_langgraph_app = app.state.app_state.langgraph_apps[session_id]

    formatted_history = [
        HumanMessage(content=msg["content"]) if msg["role"] == "user" else AIMessage(content=msg["content"])
        for msg in request.chat_history
    ]

    config = {"configurable": {"thread_id": session_id}}

    async for msg, metadata in global_langgraph_app.astream(
        {
            "input": request.message,
            "chat_history": formatted_history,
            "use_rag": use_rag
        },
        stream_mode="messages",
        config=config
    ):
        if isinstance(msg, dict) and "chat_history" in msg:
            # This is a state update, don't yield it to the client
            continue

        if msg.content and not isinstance(msg, HumanMessage):
            # Yield each chunk as a Server-Sent Event
            yield f"data: {json.dumps({'content': msg.content})}\n\n"

    # Send end marker
    yield f"data: {json.dumps({'content': '[DONE]'})}\n\n"

@app.post("/query/{session_id}")
async def query(session_id: str, request: ChatRequest):
    """Endpoint for streaming chat responses"""
    return StreamingResponse(
        generate_stream(request, session_id),
        media_type="text/event-stream"
    )

@app.post("/upload/{session_id}")
async def upload_file(session_id: str, file: UploadFile = File(...)):
    try:
        # Define the session folder path based on session_id
        session_folder = UPLOAD_FOLDER / session_id
        # Create the session folder if it doesn't exist
        session_folder.mkdir(parents=True, exist_ok=True)

        # Define the file path within the session folder
        file_location = session_folder / file.filename
        
        # Write the file to the session folder
        with open(file_location, "wb+") as file_object:
            file_object.write(file.file.read())
        
        return JSONResponse(content={"message": f"File '{file.filename}' uploaded successfully to session '{session_id}'"}, status_code=200)
    
    except Exception as e:
        return JSONResponse(content={"message": f"An error occurred: {str(e)}"}, status_code=500)

@app.delete("/delete/{session_id}/{filename}")
async def delete_file(session_id: str, filename: str):
    try:
        # Define the file path within the specified session folder
        file_path = UPLOAD_FOLDER / session_id / filename
        
        # Check if the file exists and delete it
        if file_path.exists():
            os.remove(file_path)
            return JSONResponse(content={"message": f"File '{filename}' deleted successfully from session '{session_id}'"}, status_code=200)
        else:
            raise HTTPException(status_code=404, detail=f"File '{filename}' not found in session '{session_id}'")
    
    except Exception as e:
        return JSONResponse(content={"message": f"An error occurred: {str(e)}"}, status_code=500)

@app.delete("/delete-session/{session_id}")
async def delete_session_folder(session_id: str):
    try:
        # Define the path to the session folder
        session_folder = UPLOAD_FOLDER / session_id
        
        # Check if the session folder exists
        if session_folder.exists() and session_folder.is_dir():
            # Delete the entire session folder
            shutil.rmtree(session_folder)
            return JSONResponse(content={"message": f"Session folder '{session_id}' deleted successfully"}, status_code=200)
        else:
            raise HTTPException(status_code=404, detail=f"Session folder '{session_id}' not found")
    
    except Exception as e:
        return JSONResponse(content={"message": f"An error occurred: {str(e)}"}, status_code=500)
    
@app.post("/truncate/{session_id}")
async def truncate_database(session_id: str):
    try:
        print("Entered truncate")
        index_name = session_id
        if index_name in pc.list_indexes().names():
            pc.delete_index(index_name)
            message = f"Index '{index_name}' has been deleted successfully."
        else:
            message = f"Index '{index_name}' does not exist."
        return JSONResponse(content={"message": message}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"message": f"An error occurred: {str(e)}"}, status_code=500)

# Add cleanup endpoint for session state
@app.delete("/cleanup/{session_id}")
async def cleanup_session(session_id: str):
    try:
        # Remove session-specific state
        if session_id in app.state.app_state.langgraph_apps:
            del app.state.app_state.langgraph_apps[session_id]
        if session_id in app.state.app_state.retrievers:
            del app.state.app_state.retrievers[session_id]
        return JSONResponse(
            content={"message": f"Session {session_id} state cleaned up successfully"},
            status_code=200
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"An error occurred during session cleanup: {str(e)}"
        )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)