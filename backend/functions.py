# functions.py
import logging
import os
from pathlib import Path
from typing import List, Generator

import pinecone
from langchain.document_loaders import PyPDFLoader, Docx2txtLoader, TextLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.embeddings import HuggingFaceEmbeddings

from langchain_groq import ChatGroq
from langchain.chains import RetrievalQA
from langchain.callbacks.streaming_stdout import StreamingStdOutCallbackHandler
from fastapi.responses import StreamingResponse
from groq import Groq 

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

def extract_and_vectorize(pc,spec,embeddings):
    print("Entered extract")
    UPLOAD_FOLDER = Path("uploaded_files")
    all_text = ""

    for file_path in UPLOAD_FOLDER.glob("*"):
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

    # Split text into chunks
    text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
    chunks = text_splitter.split_text(all_text)

    index_name = "bruno"

    if index_name not in pc.list_indexes().names():
        pc.create_index(index_name, dimension=768, metric="cosine",spec=spec)
    else:
        print("already there")

    index = pc.Index(index_name)
    from langchain.vectorstores import Pinecone
    vector_store = Pinecone.from_texts(chunks, embeddings, index_name=index_name)

def query_llm(prompt: str, file_uploaded: bool, groq_api_key: str, embeddings) -> Generator[str, None, None]:
    print("Entered query llm")
    
    client = Groq(api_key=groq_api_key)

    llm = ChatGroq(
        groq_api_key=groq_api_key,
        model_name="llama3-70b-8192",
        streaming=True,
        callbacks=[StreamingStdOutCallbackHandler()]
    )

    if file_uploaded:
        from langchain.vectorstores import Pinecone
        vector_store = Pinecone.from_existing_index(index_name="bruno", embedding=embeddings)
        retriever = vector_store.as_retriever(search_kwargs={"k": 3})
        qa_chain = RetrievalQA.from_chain_type(
            llm=llm,
            chain_type="stuff",
            retriever=retriever,
            return_source_documents=False,
        )
        
        for chunk in qa_chain.stream({"query": prompt}):
            if "result" in chunk:
                logging.debug(f"Generated chunk: {chunk['result']}")
                yield chunk["result"]

    else:
        messages = [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": prompt}
        ]

        try:

            stream = client.chat.completions.create(
                messages=messages,
                model="llama3-70b-8192",
                temperature=0.5,
                max_tokens=1024,
                top_p=1,
                stream=True
            )

            for chunk in stream:
                if chunk.choices[0].delta.content is not None:
                    content = chunk.choices[0].delta.content
                    yield content
                else:
                    logger.debug("Chunk content is None, skipping")
            
        except Exception as e:
            logger.error(f"Error during Groq API call: {str(e)}", exc_info=True)
            raise

def truncate_vector_db(pc):
    print("Entered truncate")
    index_name = "bruno"
    if index_name in pc.list_indexes().names():
        index = pc.Index(index_name)
        index.delete(delete_all=True)
        return f"Index '{index_name}' has been truncated successfully."
    else:
        return f"Index '{index_name}' does not exist."
