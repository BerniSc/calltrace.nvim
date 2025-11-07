# intermediary.py

from helpers import helper_function, another_helper

def start_process():
    print("Starting process")
    helper_function()
    another_helper()

def intermediary_function():
    print("Intermediary function")
    helper_function()
