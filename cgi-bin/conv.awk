## this is a gawk script
##  I hacked this together quickly to massage the httpd output.  The
##  mappings are something like this:

##    %  -> %25
##    &  -> %26
##    |  -> %7C
##    /  -> %2F
##

## that is, they're represented by their hex codes, preceded by a '%'.

## this could probably be done in one line of perl code or something.
## crash@cygnus.com 12/15/94


{ 
    result=""
    indexresult=index($0, "%")
    if (indexresult==0)  { print ; exit }

    while (indexresult != 0) {
       new=substr($0, 0, indexresult-1)
       code=substr($0, indexresult+1, 2)

       lnibble=substr(code, 2, 1)
       hnibble=substr(code, 1, 1)

       if (lnibble == "A" || lnibble == "a")
          lscratch=10
       else if (lnibble == "B" || lnibble == "b")
          lscratch=11
       else if (lnibble == "C" || lnibble == "c")
          lscratch=12
       else if (lnibble == "D" || lnibble == "d")
          lscratch=13
       else if (lnibble == "E" || lnibble == "e")
          lscratch=14
       else if (lnibble == "F" || lnibble == "f")
          lscratch=15
       else
          lscratch=lnibble

       if (hnibble == "A" || hnibble == "a")
          hscratch=10
       else if (hnibble == "B" || hnibble == "b")
          hscratch=11
       else if (hnibble == "C" || hnibble == "c")
          hscratch=12
       else if (hnibble == "D" || hnibble == "d")
          hscratch=13
       else if (hnibble == "E" || hnibble == "e")
          hscratch=14
       else if (hnibble == "F" || hnibble == "f")
          hscratch=15
       else
          hscratch=hnibble

       ascii=(hscratch * 16 ) + lscratch

       if (ascii < 32)
           ascii=32       # no control characters allowed!

       code=sprintf("%c", ascii)

       result=sprintf("%s%s%s", result, new, code)

       $0=substr($0, indexresult+3, length($0)-indexresult-2)
    indexresult=index($0, "%")
    } # while
    print result $0
}
