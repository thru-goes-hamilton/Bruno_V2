from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from functions import extract_and_vectorize, query_llm, truncate_vector_db
import os
from pathlib import Path
from langchain.embeddings import HuggingFaceEmbeddings
from langchain.vectorstores import Pinecone
from pinecone import ServerlessSpec
from dotenv import load_dotenv

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

UPLOAD_FOLDER = Path("uploaded_files")
UPLOAD_FOLDER.mkdir(exist_ok=True)

pinecone_apikey=os.getenv("PINECONE_API_KEY")
print(f"Pinecone API: {pinecone_apikey}")
groq_apikey=os.getenv("GROQ_API_KEY")
pinecone_environment=os.getenv("PINECONE_ENVIRONMENT")

embeddings = HuggingFaceEmbeddings()

from pinecone import Pinecone
pc = Pinecone(pinecone_apikey)

cloud ='aws'
region =pinecone_environment

spec = ServerlessSpec(cloud=cloud, region=region)

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    try:
        file_location = UPLOAD_FOLDER / file.filename
        with open(file_location, "wb+") as file_object:
            file_object.write(file.file.read())
        extract_and_vectorize()
        return JSONResponse(content={"message": f"File '{file.filename}' uploaded successfully"}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"message": f"An error occurred: {str(e)}"}, status_code=500)

@app.delete("/delete/{filename}")
async def delete_file(filename: str):
    try:
        file_path = UPLOAD_FOLDER / filename
        if file_path.exists():
            os.remove(file_path)
            return JSONResponse(content={"message": f"File '{filename}' deleted successfully"}, status_code=200)
        else:
            raise HTTPException(status_code=404, detail=f"File '{filename}' not found")
    except Exception as e:
        return JSONResponse(content={"message": f"An error occurred: {str(e)}"}, status_code=500)

@app.delete("/delete-all")
async def delete_all_files():
    try:
        deleted_files = []
        for file_path in UPLOAD_FOLDER.glob("*"):
            if file_path.is_file():
                os.remove(file_path)
                deleted_files.append(file_path.name)

        if deleted_files:
            return JSONResponse(content={"message": f"All files deleted successfully: {', '.join(deleted_files)}"}, status_code=200)
        else:
            return JSONResponse(content={"message": "No files found to delete."}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"message": f"An error occurred: {str(e)}"}, status_code=500)

@app.post("/extract-and-vectorize")
async def extract_and_vectorize_route():
    try:
        extract_and_vectorize(pc,spec,embeddings)
        print("Succesfully uploaded vectors")

        return JSONResponse(content={"message": "Extraction and vectorization completed successfully"}, status_code=200)
    except Exception as e:

        raise HTTPException(status_code=500, detail=f"An error occurred during extraction and vectorization: {str(e)}")

@app.post("/query")
def query(prompt: str):
    try:
        # Check if the uploaded_files directory is empty
        file_uploaded = any(UPLOAD_FOLDER.glob("*"))  # True if there are any files
        if(file_uploaded):
            print("Entered file_uploaded check")
            extract_and_vectorize(pc,spec,embeddings)
            print("Succesfully uploaded vectors")
        response_generator = list(query_llm(prompt, file_uploaded=file_uploaded, groq_api_key=groq_apikey, embeddings=embeddings))
        if(file_uploaded):
            message = truncate_vector_db(pc=pc)
            print("Succesfully truncated")
        return StreamingResponse((chunk for chunk in response_generator), media_type="text/plain")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"An error occurred: {str(e)}")

@app.post("/truncate")
async def truncate_database():
    try:
        message = truncate_vector_db(pc=pc)
        return JSONResponse(content={"message": message}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"message": f"An error occurred: {str(e)}"}, status_code=500)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)