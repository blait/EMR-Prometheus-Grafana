package com.amazonaws.support.training.emr;

import java.io.IOException;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.Reducer;
import org.apache.hadoop.mapreduce.lib.input.TextInputFormat;
import org.apache.hadoop.mapreduce.lib.output.TextOutputFormat;
import org.apache.hadoop.util.GenericOptionsParser;
import org.apache.hadoop.util.StringUtils;

public class Wordcount {
  public static class WordcountMapper extends Mapper<LongWritable, Text, Text, LongWritable> {
    private Text outKey = new Text();
    
    private static final LongWritable ONE = new LongWritable(1L);
    
    public void map(LongWritable key, Text value, Mapper<LongWritable, Text, Text, LongWritable>.Context context) throws IOException, InterruptedException {
      String[] words = StringUtils.split(value.toString(), ' ');
      
      for (String word : words) {
        outKey.set(word);
        context.write(outKey, ONE);
      } 
    }
  }
  
  public static class WordcountReducer extends Reducer<Text, LongWritable, Text, LongWritable> {
    private LongWritable outValue = new LongWritable();
    
    public void reduce(Text key, Iterable<LongWritable> values, Reducer<Text, LongWritable, Text, LongWritable>.Context context) throws IOException, InterruptedException {
      long sumViews = 0L;
      
      for (LongWritable value : values)
        sumViews += value.get(); 
      
      outValue.set(sumViews);
      
      context.write(key, outValue);
    }
  }
  
  public static void main(String[] args) throws Exception {
    Configuration conf = new Configuration();
    
    String[] otherArgs = new GenericOptionsParser(conf, args).getRemainingArgs();
    
    Path input = new Path(otherArgs[0]);
    Path output = new Path(otherArgs[1]);
    
    Job job = Job.getInstance(conf);
    
    job.setJarByClass(Wordcount.class);
    job.setJobName("Wordcount");
    
    job.setMapperClass(WordcountMapper.class);
    job.setReducerClass(WordcountReducer.class);

    job.setInputFormatClass(TextInputFormat.class);
    job.setOutputFormatClass(TextOutputFormat.class);
    
    job.setMapOutputKeyClass(Text.class);
    job.setMapOutputValueClass(LongWritable.class);
    
    job.setOutputKeyClass(Text.class);
    job.setOutputValueClass(LongWritable.class);
    
    TextInputFormat.addInputPath(job, input);
    TextOutputFormat.setOutputPath(job, output);
    
    System.exit(job.waitForCompletion(true) ? 0 : 1);
  }
}
