1) Copie les fichiers sur chaque machine
2) fait le preflight.sh poru être sur que ca casse pas, si y'a un truc, tu m'envoi un message et on checkera ensemble =)
chmod +x preflight.sh
sudo ./preflight.sh

3) edite vars-opennebula.env (IP/hostnames/bridge/etc...)
4) Sur le NODE (Serveur 2) :
chmod +x setup-node-kvm.sh
sudo ./setup-node-kvm.sh

5) Sur le FRONTEND (Serveur 1) :
chmod +x setup-frontend.sh
sudo ./setup-frontend.sh

À la fin, ouvre Sunstone : http://FRONTEND_IP:9869/ (t'auras l'adresse a la fin de l'install)
Login: oneadmin — Mot de passe : sudo cat /var/lib/one/.one/one_auth
