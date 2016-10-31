import sys.args

def main(argv):
    grammar = "kant.xml"
try:    
    opts, args = getopt.getopt(argv, "hg:d", ["help", "grammar="])
except getopt.GetoptError:
    usage()
    sys.exit(2)
for opt, arg in opts:
    if opt in ("-h", "--help"):
        usage()
        sys.exit()
    elif opt == '-d':
        global _debug
        _debug = 1
    elif opt in ("-g", "--grammar"):
        grammar = arg

source = "".join(args)

k = KantGenerator(grammar, source)
print (k)