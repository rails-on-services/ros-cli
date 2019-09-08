#!/usr/bin/env python3
import subprocess
import os
import json
import sys

def external_data():
  # Make sure the input is a valid JSON.
  input_json = sys.stdin.read()
  try:
      input_dict = json.loads(input_json)
  except ValueError as value_error:
      sys.exit(value_error)
  
  # AWS profile
  aws_profile=input_dict["aws_profile"]  
  
  # Kube config
  config_name=input_dict["config_name"]
  homedir=os.path.expanduser('~')
  kubeconfigpath = "{}/.kube/{}".format(homedir, config_name)
  
  # Check if kubeconfig file exists
  if not os.path.isfile(kubeconfigpath) : 
    sys.stdout.write(json.dumps({"LoadBalancerArn": ""}))
    sys.exit()

  # Get istio load balancer hostname attached to our cluster  
  try:
    hostname=subprocess.check_output(['kubectl', '--kubeconfig', \
      '{}'.format(kubeconfigpath), \
      '-n', 'istio-system', \
      'get', 'ingress', \
      'istio-alb-ingressgateway', \
      '-o', 'jsonpath={.status.loadBalancer.ingress[*].hostname}']).decode('utf-8')
  except Exception: 
    sys.stdout.write(json.dumps({"LoadBalancerArn": ""}))
    sys.exit()

  # Get all load load balancers for our account
  try: 
    loadbalancers=subprocess.check_output(['aws', 'elbv2', \
      'describe-load-balancers',  
      '--profile', '{}'.format(aws_profile), \
      '--query', 'LoadBalancers[*]', \
      '--output', 'json'])
    json_lb = json.loads(loadbalancers)    
  except Exception: 
    sys.stdout.write(json.dumps({"LoadBalancerArn": ""}))
    sys.exit()  

  # Look for LB that matches istio LB hostname, output first match
  for i in json_lb:
    if i["DNSName"] == hostname:
      if i["State"]['Code'] == 'active':
        sys.stdout.write(json.dumps({"LoadBalancerArn": i["LoadBalancerArn"]}))
        sys.exit()

  sys.stdout.write(json.dumps({"LoadBalancerArn": ""}))
  sys.exit()
  
if __name__ == "__main__":
  external_data()