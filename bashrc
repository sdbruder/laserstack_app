source /etc/profile

echo "[client]" >  ~/.my.cnf
echo "host=db"  >> ~/.my.cnf
[ -n "$MYSQL_USER" ]     && echo "user=${MYSQL_USER}"         >> ~/.my.cnf
[ -n "$MYSQL_PASSWORD" ] && echo "password=${MYSQL_PASSWORD}" >> ~/.my.cnf

echo ""        >>  ~/.my.cnf
echo "[mysql]" >>  ~/.my.cnf
[ -n "$MYSQL_DATABASE" ] && echo "database=${MYSQL_DATABASE}" >> ~/.my.cnf
