# If we trace goal->foo we get 4 results for loopdetection=simplified and 6 for loopdetection=complete
def foo():
    return;

def h2():
    h1()
    foo()

def h1():
    h2()
    foo()

def goal():
    h1();
    h2()
