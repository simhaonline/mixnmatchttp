#!/bin/bash

REQFILE="${1:-logs/requests.log}"
OUTFILE="${2:-logs/requests_result.md}"
TMPFILE="${OUTFILE}.unsorted"
if [[ $(uname) == Darwin* ]] ; then
  AWK='gawk'
else
  AWK='awk'
fi
DEBUG=0

${AWK} -v debug=${DEBUG} '
BEGIN {
  IGNORECASE=1
  colwidths[1]=20
  colwidths[2]=26
  colwidths[3]=11
  colwidths[4]=11
  colwidths[5]=15
  colwidths[6]=15
  colwidths[7]=11
  colwidths[8]=11
  fmtHdr=""
  hdrSep=""
  for (i in colwidths) {
    fmtHdr=fmtHdr "| %-" colwidths[i] "s "
    hdrSep=hdrSep "| :" gensub(/ /, "-", "g", sprintf("%-" colwidths[i]-2 "s", "")) ": "
  }
  fmtHdr=fmtHdr "|\n"
  hdrSep=hdrSep "|\n"
  printf fmtHdr, "BROWSER", "METHOD", "ORIGIN", "CREDENTIALS", "SENDS ORIGIN", "PREFLIGHT", "COOKIE", "READ BY JS"

  print hdrSep
}
/[^ ]/ {
  sub("\r", "", $0)
  # look for first non-blank line after start
  if (newReq) {
    newReq=0 
    if (debug > 1) { print "DEBUG: " $0 }
    requested=match($0,
      /^(GET|POST|OPTIONS|HEAD|DELETE|PUT) \/secret\/secret\.[a-z]+\?origin=([^&]*)&creds=([01])&via=([^&]*)&reqBy=([^&]+)[^ ]* HTTP\/[0-9\.]+$/,
      mArr)
    if (requested) {
      method=mArr[1]
      allowOrigin=gensub(/%3a/, ":", "g", tolower(mArr[2]))
      allowOrigin=gensub(/%2f/, "/", "g", allowOrigin)
      reqOrigin=gensub(/%3a/, ":", "g", tolower(mArr[5]))
      reqOrigin=gensub(/%2f/, "/", "g", reqOrigin)
      if (allowOrigin == reqOrigin) {
        allowOrigin="{ECHO}"
      }
      if (debug > 1) { print "DEBUG: allowOrigin: " allowOrigin }
      allowCreds=mArr[3]
      exfMethod=mArr[4]
    } else {
      exfiltrated=match($0,
        /^POST \/sop\/getSecret.html\?.*&allowOrigin=([^&]*)&allowCreds=([01])&method=([^&]+)&via=([^&]+) HTTP\/[0-9\.]+$/,
        mArr)
      if (exfiltrated) {
        allowOrigin=gensub(/%3a/, ":", "g", tolower(mArr[1]))
        allowOrigin=gensub(/%2f/, "/", "g", allowOrigin)
        if (debug > 1) { print "DEBUG: allowOrigin: " allowOrigin }
        allowCreds=mArr[2]
        method=mArr[3]
        exfMethod=mArr[4]
      }
    }
    if (debug > 1) { print "DEBUG: requested: " requested ", exfiltrated: " exfiltrated }
  }
}
(requested || exfiltrated) {
  # look for the Access-Control-Request-Method, Origin or the Cookie
  # after a request for the secret
  if (requested && match($0, /^Access-Control-Request-Method: *(.*)/, mArr)) {
    method=mArr[1]
    if (debug > 1) { print "DEBUG: preflight for " method }
    preflight="Y"
  }
  if (requested && match($0, /^Cookie: *SESSION=/)) {
    if (debug > 1) { print "DEBUG: " $0 }
    cookie="Y"
  }
  if (requested && match($0, /^Origin:/)) {
    if (debug > 1) { print "DEBUG: " $0 }
    sendsOrigin="Y"
  }
  # look for the Host after exfiltration and compare to allowOrigin
  if (exfiltrated && match($0, /^Host: *(.*)/, mArr)) {
    if (debug > 1) {
      print "DEBUG: Comparing reqOrigin " mArr[1] " to allowOrigin " gensub(/^https?:\/\//, "", "1", allowOrigin)
    }
    if (mArr[1] == gensub(/^https?:\/\//, "", "1", allowOrigin)) {
      allowOrigin="{ECHO}" # clearly shows when the allowOrigin is allowed in the table
    }
  }
  # look for the User-Agent
  if (match($0, /^User-Agent: *([^\(]*) *(\([^\)]*\))? *(.*)/, mArr)) {
    if (mArr[2]) {
      os=gensub(/^\(|\)$/, "", "g", mArr[2])
      uaFull=mArr[1] " " mArr[3]
    }
    else {
      os=""
      uaFull=mArr[1]
    }

    if (uaFull == "contype") {
      # IE being an idiot
      ua=uaOLD
    }
    else {
      numF=patsplit(uaFull, uaFields, /[A-Za-z]+\/[0-9\.]+/)
      # split(os, osFields, /; */)
      if (debug > 1) {
        printf "DEBUG: UA: os=" os ", numF=" numF ", uaFields=["
        for (i = 0; i <= numF ; i++) { printf uaFields[i] ", " }
        print "]"
      }
      ua=""
      if (numF > 1) {
        if ( ( uaFields[1] ~ /Mozilla\// && (uaFields[numF] ~ /OPR\// || uaFields[numF-1] == "Opera") ) ||
          ( uaFields[1] ~ /Opera\// && uaFields[numF] ~ /Version\// ) ) {
          # OPERA v1,2,3
          if (debug > 1) { print "DEBUG: UA is Opera v1,2 or 3" }
          ua="Opera " gensub(/.*\//, "", "1", uaFields[numF])
        }
        else if (uaFields[1] ~ /Opera\//) {
          # OPERA v4
          if (debug > 1) { print "DEBUG: UA is Opera v4" }
          ua=gensub(/\//, " ", "1", uaFields[1])
        }
        else if (uaFields[numF-1] ~ /Chrome\//) {
          # CHROME
          if (debug > 1) { print "DEBUG: UA is Chrome" }
          ua=gensub(/\//, " ", "1", uaFields[numF-1])
        }
        else if (uaFields[numF] ~ /(Firefox)\//) {
          # FIREFOX
          if (debug > 1) { print "DEBUG: UA is Firefox" }
          ua=gensub(/\//, " ", "1", uaFields[numF])
        }
        else if (uaFields[numF] ~ /(Edge)\//) {
          # EDGE
          if (debug > 1) { print "DEBUG: UA is Edge" }
          ua=gensub(/\//, "HTML ", "1", uaFields[numF])
        }
        else if (uaFields[numF] ~ /(Safari)\//) {
          # SAFARI
          if (debug > 1) { print "DEBUG: UA is Safari" }
          version=""
          for (i in uaFields) {
            if (uaFields[i] ~ /Version\// ) {
              version=gensub(/.*\//, "", "1", uaFields[i])
            }
          }
          if (! version) {
            version=gensub(/.*\//, "", "1", uaFields[numF]) # WebKit version
          }
          ua=gensub(/\//, " ", "1", uaFields[numF])
        }
      }
      if (! ua) {
        if (os ~ /MSIE|Trident/) {
          # INTERNET EXPLORER
          if (debug > 1) { print "DEBUG: UA is IE" }
          match(os, /(Windows NT *)([0-9\.]+)/, mArr)
          WinVersion=mArr[2]
          match(os, /(MSIE *|rv *: *)([0-9\.]+)/, mArr)
          IEVersion=mArr[2]
          if (! IEVersion) {
            IEVersion="(Unknown)"
          }
          ua="IE " IEVersion " (Win " WinVersion ")"
        }
        else if (numF == 1) {
          # OPERA v5 and some others maybe?
          ua=gensub(/\//, " ", "1", uaFields[1])
        }
        else {
          # UNKNOWN
          if (debug > 1) { print "DEBUG: UA is Unknown" }
          ua=uaFull
        }
      }
    }
  }
}
/^----- Request Start ----->/ {
  newReq=1
  allowOrigin=""
  allowCreds=""
  sendsOrigin=""
  method=""
  preflight=""
  exfMethod=""
  cookie=""
  # keep it in case the next one is IE doing a HEAD with UA=contype
  uaOLD=ua
  ua=""
}
/^<----- Request End -----/ {

  if (requested || exfiltrated) {
    id=ua "@" allowOrigin "@" allowCreds "@" method "@" exfMethod
    if (preflight) {
      result[id]["preflight"]=preflight (cookie ? " (with Cookie)" : "")
    } else if (requested) {
      result[id]["ua"]=ua
      result[id]["allowOrigin"]=allowOrigin
      result[id]["allowCreds"]=allowCreds
      result[id]["sendsOrigin"]=sendsOrigin
      result[id]["method"]=method " (via " exfMethod ")"
      result[id]["cookie"]=cookie
    } else if (exfiltrated) {
      result[id]["read"]="Y"
    }
    if (debug) {
      print "DEBUG: END: id: " id ", requested: " requested ", exfiltrated: " exfiltrated
      if (result[id]["ua"]) {
        print "DEBUG: END: result[id]=["
        print "DEBUG:   " ua ": "
        for (f in result[id]) {
          print "DEBUG:     " f ": " result[id][f] "; "
        }
        print "DEBUG:  ]"
      }
    }
  }

  requested=0
  exfiltrated=0
}
END {
  for (id in result) {
    printf fmtHdr, result[id]["ua"], result[id]["method"], result[id]["allowOrigin"], result[id]["allowCreds"], result[id]["sendsOrigin"], result[id]["preflight"], result[id]["cookie"], result[id]["read"]
  }
}
' "${REQFILE}" > "${TMPFILE}"
[[ ${DEBUG} -eq 0 ]] || exit 0

############################################################
DEBUG=0

# Sort the table
IFS=$'\n' read -d '' -a browsers < <(tail -n+3 "${TMPFILE}" | cut -d\| -f2 | sort -u)
# don't sort them by HTTP method, only exfiltration method; keep the order in which requests were sent
IFS=$'\n' read -d '' -a exfMethods < <(tail -n+3 "${TMPFILE}" | egrep -o 'via [^ )]+' | sort -u)
IFS=$'\n' read -d '' -a origins < <(tail -n+3 "${TMPFILE}" | cut -d\| -f4 | sort -u)
sep=$(sed -n '2p' "${TMPFILE}" | tr ':-' '~')
SPECIAL_CHARS=('\\' '\(' '\)' '\[' '\]' '\.' '\^' '\$' '\+' '\?' '\*' '\|' '\{' '\}')

if [[ ${DEBUG} -ne 0 ]] ; then
  echo "browsers:"
  printf "  %s\n" "${browsers[@]}"
  echo "exfMethods:"
  printf "  %s\n" "${exfMethods[@]}"
  echo "origins:"
  printf "  %s\n" "${origins[@]}"
fi

head -n2 "${TMPFILE}" > "${OUTFILE}"
for browser in "${browsers[@]}" ; do
  for c in "${SPECIAL_CHARS[@]}" ; do
    browser="${browser//${c}/${c}}"
  done
  for origin in "${origins[@]}" ; do
    for c in "${SPECIAL_CHARS[@]}" ; do
      origin="${origin//${c}/${c}}"
    done
    for creds in 1 0 ; do
      for method in "${exfMethods[@]}" ; do
        [[ ${DEBUG} -eq 0 ]] || echo '^\| *'"${browser}"' *\| *'"[A-Z]+ \(${method}\)"' *\| *'"${origin}"' *\| *'"${creds}"' *\|' 1>&2
        egrep '^\| *'"${browser}"' *\| *'"[A-Z]+ \(${method}\)"' *\| *'"${origin}"' *\| *'"${creds}"' *\|' "${TMPFILE}"
      done
      echo "${sep}"
    done
  done
done | uniq >> "${OUTFILE}"

[[ ${DEBUG} -eq 0 ]] && rm "${TMPFILE}"
