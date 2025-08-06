#!/usr/bin/env python3
"""
Spark Application Metrics Exporter for Prometheus
Collects individual Spark application resource usage from YARN ResourceManager and Spark History Server
"""

import requests
import json
import time
import logging
from prometheus_client import start_http_server, Gauge, Counter, Info
from datetime import datetime
import argparse
import sys
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class SparkApplicationExporter:
    def __init__(self, yarn_rm_host, spark_history_host=None, port=8080, scrape_interval=30):
        self.yarn_rm_host = yarn_rm_host
        self.spark_history_host = spark_history_host or yarn_rm_host
        self.port = port
        self.scrape_interval = scrape_interval
        
        # Prometheus metrics
        self.spark_app_info = Info('spark_application_info', 'Spark application information', 
                                 ['cluster_id', 'app_id', 'app_name', 'user', 'queue', 'state'])
        
        self.spark_app_memory_used = Gauge('spark_application_memory_used_mb', 
                                         'Memory used by Spark application in MB',
                                         ['cluster_id', 'app_id', 'app_name', 'user', 'queue'])
        
        self.spark_app_memory_reserved = Gauge('spark_application_memory_reserved_mb',
                                             'Memory reserved by Spark application in MB', 
                                             ['cluster_id', 'app_id', 'app_name', 'user', 'queue'])
        
        self.spark_app_vcores_used = Gauge('spark_application_vcores_used',
                                         'vCores used by Spark application',
                                         ['cluster_id', 'app_id', 'app_name', 'user', 'queue'])
        
        self.spark_app_vcores_reserved = Gauge('spark_application_vcores_reserved',
                                             'vCores reserved by Spark application',
                                             ['cluster_id', 'app_id', 'app_name', 'user', 'queue'])
        
        self.spark_app_containers = Gauge('spark_application_containers_total',
                                        'Total containers used by Spark application',
                                        ['cluster_id', 'app_id', 'app_name', 'user', 'queue'])
        
        self.spark_app_duration = Gauge('spark_application_duration_seconds',
                                      'Duration of Spark application in seconds',
                                      ['cluster_id', 'app_id', 'app_name', 'user', 'queue', 'state'])
        
        self.spark_app_progress = Gauge('spark_application_progress_percent',
                                      'Progress of Spark application in percent',
                                      ['cluster_id', 'app_id', 'app_name', 'user', 'queue'])
        
        # Executor metrics
        self.spark_executor_memory = Gauge('spark_executor_memory_used_mb',
                                         'Memory used by Spark executor in MB',
                                         ['cluster_id', 'app_id', 'executor_id', 'host'])
        
        self.spark_executor_cores = Gauge('spark_executor_cores_total',
                                        'Total cores allocated to Spark executor',
                                        ['cluster_id', 'app_id', 'executor_id', 'host'])
        
        self.spark_executor_tasks = Gauge('spark_executor_tasks_total',
                                        'Total tasks completed by Spark executor',
                                        ['cluster_id', 'app_id', 'executor_id', 'host'])
        
        # Counters
        self.scrape_errors = Counter('spark_exporter_scrape_errors_total',
                                   'Total number of scrape errors',
                                   ['source'])
        
        self.apps_scraped = Counter('spark_exporter_apps_scraped_total',
                                  'Total number of applications scraped')

    def get_yarn_applications(self):
        """Get running Spark applications from YARN ResourceManager"""
        try:
            url = f"http://{self.yarn_rm_host}:8088/ws/v1/cluster/apps"
            params = {
                'states': 'RUNNING,SUBMITTED,ACCEPTED',
                'applicationTypes': 'SPARK'
            }
            
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            
            data = response.json()
            apps = data.get('apps', {}).get('app', [])
            
            # Handle single app case
            if isinstance(apps, dict):
                apps = [apps]
                
            logger.info(f"Found {len(apps)} Spark applications from YARN")
            return apps
            
        except Exception as e:
            logger.error(f"Error fetching YARN applications: {e}")
            self.scrape_errors.labels(source='yarn').inc()
            return []

    def get_spark_application_details(self, app_id):
        """Get detailed Spark application info from History Server"""
        try:
            # Try multiple possible endpoints
            endpoints = [
                f"http://{self.spark_history_host}:18080/api/v1/applications/{app_id}",
                f"http://{self.spark_history_host}:4040/api/v1/applications/{app_id}",
                f"http://{self.spark_history_host}:4041/api/v1/applications/{app_id}"
            ]
            
            for endpoint in endpoints:
                try:
                    response = requests.get(endpoint, timeout=5)
                    if response.status_code == 200:
                        return response.json()
                except:
                    continue
                    
            return None
            
        except Exception as e:
            logger.debug(f"Could not get Spark details for {app_id}: {e}")
            return None

    def get_spark_executors(self, app_id):
        """Get executor information for a Spark application"""
        try:
            endpoints = [
                f"http://{self.spark_history_host}:18080/api/v1/applications/{app_id}/executors",
                f"http://{self.spark_history_host}:4040/api/v1/applications/{app_id}/executors",
                f"http://{self.spark_history_host}:4041/api/v1/applications/{app_id}/executors"
            ]
            
            for endpoint in endpoints:
                try:
                    response = requests.get(endpoint, timeout=5)
                    if response.status_code == 200:
                        return response.json()
                except:
                    continue
                    
            return []
            
        except Exception as e:
            logger.debug(f"Could not get executors for {app_id}: {e}")
            return []

    def extract_cluster_id(self, app_name, tracking_url):
        """Extract cluster ID from application info"""
        # Try to extract from tracking URL
        if tracking_url and 'amazonaws.com' in tracking_url:
            try:
                # Extract from EMR tracking URL pattern
                parts = tracking_url.split('/')
                for part in parts:
                    if part.startswith('j-') and len(part) > 10:
                        return part
            except:
                pass
        
        # Try to extract from application name
        if app_name:
            # Look for cluster ID pattern in app name
            import re
            match = re.search(r'j-[A-Z0-9]{13}', app_name)
            if match:
                return match.group(0)
        
        return 'unknown'

    def update_metrics(self):
        """Update all Prometheus metrics"""
        try:
            apps = self.get_yarn_applications()
            
            # Clear previous metrics
            self.spark_app_memory_used.clear()
            self.spark_app_memory_reserved.clear()
            self.spark_app_vcores_used.clear()
            self.spark_app_vcores_reserved.clear()
            self.spark_app_containers.clear()
            self.spark_app_duration.clear()
            self.spark_app_progress.clear()
            self.spark_executor_memory.clear()
            self.spark_executor_cores.clear()
            self.spark_executor_tasks.clear()
            
            for app in apps:
                try:
                    app_id = app.get('id', '')
                    app_name = app.get('name', '')
                    user = app.get('user', '')
                    queue = app.get('queue', '')
                    state = app.get('state', '')
                    
                    # Extract cluster ID
                    cluster_id = self.extract_cluster_id(app_name, app.get('trackingUrl', ''))
                    
                    # Basic YARN metrics
                    memory_used = app.get('allocatedMB', 0)
                    memory_reserved = app.get('reservedMB', 0)
                    vcores_used = app.get('allocatedVCores', 0)
                    vcores_reserved = app.get('reservedVCores', 0)
                    containers = app.get('runningContainers', 0)
                    
                    # Calculate duration
                    start_time = app.get('startedTime', 0)
                    finish_time = app.get('finishedTime', 0)
                    current_time = int(time.time() * 1000)
                    
                    if finish_time > 0:
                        duration = (finish_time - start_time) / 1000
                    else:
                        duration = (current_time - start_time) / 1000
                    
                    # Progress
                    progress = app.get('progress', 0)
                    
                    # Labels
                    labels = [cluster_id, app_id, app_name, user, queue]
                    
                    # Update basic metrics
                    self.spark_app_memory_used.labels(*labels).set(memory_used)
                    self.spark_app_memory_reserved.labels(*labels).set(memory_reserved)
                    self.spark_app_vcores_used.labels(*labels).set(vcores_used)
                    self.spark_app_vcores_reserved.labels(*labels).set(vcores_reserved)
                    self.spark_app_containers.labels(*labels).set(containers)
                    self.spark_app_duration.labels(*labels, state).set(duration)
                    self.spark_app_progress.labels(*labels).set(progress)
                    
                    # Application info
                    self.spark_app_info.labels(*labels, state).info({
                        'started_time': str(start_time),
                        'tracking_url': app.get('trackingUrl', ''),
                        'application_type': app.get('applicationType', ''),
                        'final_status': app.get('finalStatus', '')
                    })
                    
                    # Get executor details if available
                    executors = self.get_spark_executors(app_id)
                    for executor in executors:
                        executor_id = executor.get('id', '')
                        host = executor.get('hostPort', '').split(':')[0] if ':' in executor.get('hostPort', '') else executor.get('hostPort', '')
                        
                        exec_memory = executor.get('memoryUsed', 0) / (1024 * 1024)  # Convert to MB
                        exec_cores = executor.get('totalCores', 0)
                        exec_tasks = executor.get('totalTasks', 0)
                        
                        self.spark_executor_memory.labels(cluster_id, app_id, executor_id, host).set(exec_memory)
                        self.spark_executor_cores.labels(cluster_id, app_id, executor_id, host).set(exec_cores)
                        self.spark_executor_tasks.labels(cluster_id, app_id, executor_id, host).set(exec_tasks)
                    
                    self.apps_scraped.inc()
                    
                except Exception as e:
                    logger.error(f"Error processing app {app.get('id', 'unknown')}: {e}")
                    self.scrape_errors.labels(source='processing').inc()
                    
            logger.info(f"Updated metrics for {len(apps)} applications")
            
        except Exception as e:
            logger.error(f"Error in update_metrics: {e}")
            self.scrape_errors.labels(source='general').inc()

    def run(self):
        """Main run loop"""
        logger.info(f"Starting Spark Application Exporter on port {self.port}")
        logger.info(f"YARN ResourceManager: {self.yarn_rm_host}:8088")
        logger.info(f"Spark History Server: {self.spark_history_host}:18080")
        logger.info(f"Scrape interval: {self.scrape_interval} seconds")
        
        # Start Prometheus HTTP server
        start_http_server(self.port)
        
        while True:
            try:
                self.update_metrics()
                time.sleep(self.scrape_interval)
            except KeyboardInterrupt:
                logger.info("Shutting down...")
                break
            except Exception as e:
                logger.error(f"Unexpected error: {e}")
                time.sleep(self.scrape_interval)

def main():
    parser = argparse.ArgumentParser(description='Spark Application Metrics Exporter')
    parser.add_argument('--yarn-host', required=True, help='YARN ResourceManager hostname')
    parser.add_argument('--spark-history-host', help='Spark History Server hostname (default: same as YARN)')
    parser.add_argument('--port', type=int, default=8080, help='Exporter port (default: 8080)')
    parser.add_argument('--interval', type=int, default=30, help='Scrape interval in seconds (default: 30)')
    parser.add_argument('--log-level', default='INFO', choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'])
    
    args = parser.parse_args()
    
    # Set log level
    logging.getLogger().setLevel(getattr(logging, args.log_level))
    
    # Create and run exporter
    exporter = SparkApplicationExporter(
        yarn_rm_host=args.yarn_host,
        spark_history_host=args.spark_history_host,
        port=args.port,
        scrape_interval=args.interval
    )
    
    exporter.run()

if __name__ == '__main__':
    main()
