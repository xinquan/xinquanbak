alias ll="ls -l"
alias g="grep -r"
export PS1="\u:\w \$ "
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/X11/bin:/usr/local/bin"







alias mysql="/usr/local/mysql/bin/mysql -u root dudubird --password=123456 --auto-rehash"
alias mysqladmin="/usr/local/mysql/bin/mysqladmin -u root"
alias mysql_start="sudo /usr/local/mysql/bin/mysqld_safe 1>/dev/null 2>/dev/null &"
alias mysql_stop="/usr/local/mysql/bin/mysqladmin -u root shutdown"

alias "open_p"="sudo mv ~/Movies/.p ~/Movies/p; sudo chown -R ieagerly ~/Movies/p"
alias "close_p"="sudo mv ~/Movies/p ~/Movies/.p; sudo chown -R root ~/Movies/.p"
alias fuckGFW='ssh -qTfnN -D 7070 xinquan@98.142.220.251'
alias err="tail -f /var/log/apache2/error_log"
