#!/bin/bash
sudo gunicorn --workers=2 -D --bind=0.0.0.0:8080 app:app 
