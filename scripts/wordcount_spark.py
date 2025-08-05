#!/usr/bin/env python3

import sys
from pyspark.sql import SparkSession
from pyspark.sql.functions import explode, split, col, count

def main():
    if len(sys.argv) != 3:
        print("Usage: wordcount_spark.py <input_path> <output_path>", file=sys.stderr)
        sys.exit(1)
    
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    
    # SparkSession 생성
    spark = SparkSession.builder \
        .appName("WordCountSpark") \
        .getOrCreate()
    
    try:
        # 텍스트 파일 읽기
        text_df = spark.read.text(input_path)
        
        # 단어 카운트 수행
        word_counts = text_df \
            .select(explode(split(col("value"), " ")).alias("word")) \
            .filter(col("word") != "") \
            .groupBy("word") \
            .count() \
            .orderBy("count", ascending=False)
        
        # 결과를 파일로 저장 (탭으로 구분)
        word_counts.select(
            col("word").alias("word"),
            col("count").alias("count")
        ).write \
         .mode("overwrite") \
         .option("sep", "\t") \
         .csv(output_path, header=False)
        
        print(f"Word count completed. Results saved to: {output_path}")
        
        # 상위 10개 단어 출력 (선택사항)
        print("\nTop 10 words:")
        word_counts.show(10)
        
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        spark.stop()

if __name__ == "__main__":
    main()
