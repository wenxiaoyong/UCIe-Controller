#!/usr/bin/env python3
"""
Convert UCIe specification PDFs to text files for analysis
"""

import PyPDF2
import os
import glob
from pathlib import Path

def extract_text_from_pdf(pdf_path, output_path):
    """Extract text from PDF and save to text file"""
    try:
        with open(pdf_path, 'rb') as file:
            pdf_reader = PyPDF2.PdfReader(file)
            text = ""
            
            for page_num in range(len(pdf_reader.pages)):
                page = pdf_reader.pages[page_num]
                text += f"\n--- Page {page_num + 1} ---\n"
                text += page.extract_text()
            
            with open(output_path, 'w', encoding='utf-8') as text_file:
                text_file.write(text)
            
            print(f"Converted: {pdf_path} -> {output_path}")
            return True
            
    except Exception as e:
        print(f"Error converting {pdf_path}: {str(e)}")
        return False

def main():
    # Create output directory
    spec_dir = Path("/Users/xiaoyongwen/UCIe/docs/spec")
    text_dir = spec_dir / "text"
    text_dir.mkdir(exist_ok=True)
    
    # Find all PDF files
    pdf_files = glob.glob(str(spec_dir / "*_PDFsam_UCIe_Specification_*.pdf"))
    pdf_files.sort()
    
    print(f"Found {len(pdf_files)} PDF files to convert")
    
    for pdf_file in pdf_files:
        pdf_path = Path(pdf_file)
        # Extract page numbers from filename for better organization
        filename = pdf_path.stem
        page_info = filename.split('_')[0]
        
        text_filename = f"ucie_spec_pages_{page_info}.txt"
        text_path = text_dir / text_filename
        
        extract_text_from_pdf(pdf_file, text_path)
    
    print("\nConversion complete!")
    print(f"Text files saved in: {text_dir}")

if __name__ == "__main__":
    main()