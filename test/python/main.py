from intermediary import start_process
from foo import start_process as foo

def main():
    print("Main function")
    start_process()
    foo()

if __name__ == "__main__":
    main()
