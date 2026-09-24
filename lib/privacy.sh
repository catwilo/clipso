#!/usr/bin/env bash
# privacy.sh -- detect sensitive content (creds, private IPs, MACs, public IPs)
# and display the payload with privacy hits highlighted.

# privacy_scan <file> -> sets PRIVACY_HITS, PRIVACY_INFO_FILE (tsv: line\ttag\ttext)
privacy_scan() {
    local src="$1"
    PRIVACY_HITS=0
    PRIVACY_INFO_FILE=""
    [ "${CLIPSO_PRIVACY:-1}" = "0" ] && return 0

    local info
    info="$(mktemp "${TMPDIR:-/tmp}/clipso-priv.XXXXXX")"
    awk '
    BEGIN{ NK=split("password passwd secret api_key apikey private_key auth_key bearer access_key token client_secret db_pass jwt credentials",KWS) }
    function valid_ip(s,  a,n,i) {
        n=split(s,a,"."); if(n!=4) return 0
        for(i=1;i<=4;i++) if(a[i]!~/^[0-9]+$/||a[i]+0>255) return 0
        return 1
    }
    function is_priv(s,  a) {
        split(s,a,"."); a[1]+=0; a[2]+=0
        return(a[1]==10||(a[1]==192&&a[2]==168)||(a[1]==172&&a[2]>=16&&a[2]<=31))
    }
    function is_safe(s) {
        return(s=="1.1.1.1"||s=="8.8.8.8"||s=="8.8.4.4"||s=="9.9.9.9"||s=="1.0.0.1")
    }
    function nontrivial(v,  lv) {
        lv=tolower(v)
        if(lv~/^(true|false|null|yes|no|none|todo|changeme|example|placeholder)$/) return 0
        if(lv~/^your_/||lv~/^<[^>]*>$/||lv~/^\**$/||lv~/^x+$/) return 0
        return (length(v)>=5)
    }
    function cred_hit(line,  lo,kws,nk,kw,i,p,bef,rest,val) {
        lo=tolower(line)
        for(i=1;i<=NK;i++) {
            kw=KWS[i]; if(!(p=index(lo,kw))) continue
            bef=(p>1)?substr(lo,p-1,1):""
            if(bef~/[a-z0-9_]/) continue
            rest=substr(line,p+length(kw))
            if(rest!~/^[^=:a-zA-Z0-9]*[=:]/) continue
            match(rest,/[=:][[:space:]]*/)
            val=substr(rest,RSTART+RLENGTH)
            gsub(/^[[:space:]"]+|[[:space:]",;]+$/,"",val)
            if(nontrivial(val)) return 1
        }
        return 0
    }
    {
        tag=""
        if(cred_hit($0)) tag="CRED"
        if(!tag) { s=$0
            while(match(s,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
                ip=substr(s,RSTART,RLENGTH); s=substr(s,RSTART+RLENGTH)
                if(valid_ip(ip)&&is_priv(ip)) { tag="PRIV-IP"; break }
            }
        }
        if(!tag&&match($0,/[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]/)) {
            mac=tolower(substr($0,RSTART,RLENGTH))
            if(mac!="00:00:00:00:00:00"&&mac!="ff:ff:ff:ff:ff:ff") tag="MAC"
        }
        if(!tag) { s=$0
            while(match(s,/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
                pre=(RSTART>1)?substr(s,RSTART-1,1):""
                ip=substr(s,RSTART,RLENGTH); s=substr(s,RSTART+RLENGTH)
                if(!valid_ip(ip)||is_priv(ip)||is_safe(ip)) continue
                if(pre~/[a-zA-Z0-9.]/) continue
                split(ip,o,"."); if(o[1]+0==0||o[1]+0==127||o[1]+0==255) continue
                tag="PUB-IP"; break
            }
        }
        if(tag) print NR "\t" tag "\t" $0
    }
    ' "$src" > "$info"

    if [ ! -s "$info" ]; then rm -f "$info"; return 0; fi
    PRIVACY_HITS=$(wc -l < "$info" | tr -d ' ')
    PRIVACY_INFO_FILE="$info"
}

# privacy_display <file> <nums 0|1> -- paint the payload to tty; hits in red
privacy_display() {
    local src="$1" nums="${2:-1}"
    local tty
    { true >/dev/tty; } 2>/dev/null && tty=/dev/tty || tty=/dev/stderr

    if [ "${PRIVACY_HITS:-0}" -gt 0 ] && [ -f "${PRIVACY_INFO_FILE:-}" ]; then
        awk -v p="$PRIVACY_INFO_FILE" -v red="$RED" -v cyan="$CYAN" -v rst="$RESET" -v nums="$nums" \
        'BEGIN{while((getline ln<p)>0){split(ln,a,"\t");fl[a[1]]=a[3]}}
         {if(NR in fl) { if(nums=="1") printf "%s%4d  %s%s\n",red,NR,$0,rst; else printf "%s%s%s\n",red,$0,rst }
          else          { if(nums=="1") printf "%s%4d%s  %s\n",cyan,NR,rst,$0; else print }}' "$src" > "$tty"
    else
        if [ "$nums" = "1" ]; then
            awk -v c="$CYAN" -v r="$RESET" '{printf "%s%4d%s  %s\n",c,NR,r,$0}' "$src" > "$tty"
        else
            cat "$src" > "$tty"
        fi
    fi
}
