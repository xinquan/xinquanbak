alias ll="ls -l"
alias g="grep -r"
export PS1="\u:\w \$ "







alias mysql="/usr/local/mysql/bin/mysql -u root doggytrip --auto-rehash"
alias mysqladmin="/usr/local/mysql/bin/mysqladmin -u root"
alias mysql_start="sudo /usr/local/mysql/bin/mysqld_safe 1>/dev/null 2>/dev/null &"
alias mysql_stop="/usr/local/mysql/bin/mysqladmin -u root shutdown"

alias "open_p"="sudo mv ~/Movies/.p ~/Movies/p; sudo chown -R ieagerly ~/Movies/p"
alias "close_p"="sudo mv ~/Movies/p ~/Movies/.p; sudo chown -R root ~/Movies/.p"
alias fuckGFW='ssh -qTfnN -D 7070 xinquan@98.142.220.251'
alias err="tail -f /var/log/apache2/error_log"
