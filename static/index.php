<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head><title>Wordpress - T&M Hansson IT AB</title>
<style>
body {
	background-image: url("https://i.imgur.com/SfBe17Z.jpg");
	background-size: cover;
	font-weight: 300;
	font-size: 1em;
	line-height: 1.6em;
	font-family: 'Open Sans', Frutiger, Calibri, 'Myriad Pro', Myriad, sans-serif;
	color: white;
	height: auto;
	margin-left: auto;
	margin-right: auto;
	align: center;
	text-align: center;
}
div.logotext   {
	width: 50%;
    	margin: 0 auto;
}
div.logo   {
        background-image: url('https://www.techandme.se/wp-content/uploads/2015/01/WordPress-Logo-540x348.png');
        background-repeat: no-repeat; top center;
        width: 50%;
	height: 30%;
        margin: 0 auto;
	background-size: 40%;
	margin-left: 40%;
        margin-right: 20%;
}
pre  {
	padding:10pt;
	width: 50%
        text-align: center;
        margin-left: 20%;
	margin-right: 20%;
}
div.information {
        align: center;
	width: 50%;
        margin: 10px auto;
	display: block;
        padding: 10px;
        background-color: rgba(0,0,0,.3);
        color: #fff;
        text-align: left;
        border-radius: 3px;
        cursor: default;
}
/* unvisited link */
a:link {
    color: #FFFFFF;
}
/* visited link */
a:visited {
    color: #FFFFFF;
}
/* mouse over link */
a:hover {
    color: #E0E0E0;
}
/* selected link */
a:active {
    color: #E0E0E0;
}
</style>

<br>
<div class="logo">
</div>
<div class="logotext">
<h2>Wordpress VM - <a href="https://www.techandme.se/pre-configured-wordpress-vm/" target="_blank">T&M Hansson IT AB</a></h2>
</div>
<br>
<div class="information">
<p>Thank you for downloading the pre-configured Wordpress VM! If you see this page, you have successfully mounted the  Wordpress VM on the computer that will act as host for Wordpress.</p>
<p>To complete the installation, please run the setup script. You can find login details in the middle of this page.
<p>Don't hesitate to ask if you have any questions. My email is: <a href="mailto:daniel@hanssonit.se?Subject=Before%20login%20-%20Wordpress%20VM" target="_top">daniel@hanssonit.se</a> You can also check the <a href="https://www.techandme.se/install-instructions/" target="_blank">complete install instructions</a>.</p>
<p>Please <a href="https://www.techandme.se/thank_you">donate</a> if you like it. All the donations will go to server costs and developing, making this VM even better.</p>

</div>

<h2><a href="https://www.techandme.se/user-pass/" target="_blank">Login</a> to Wordpress</h2>

<div class="information">
<p>Default User:</p>
<h3>wordpress</h3>
<p>Default Password:</p>
<h3>wordpress</h3>
<p>Note: The setup script will ask you to change the default password to your own.</p>
<br>
<center>
<h3> How to mount the VM and and login:</h3>
</center>
<p>Before you can use Wordpress you have to run the setup script to complete the installation. This is easily done by just typing 'wordpress' when you log in to the terminal for the first time.</p>
<p>The full path to the setup script is: /var/scripts/wordpress-startup-script.sh. When the script is finished it will be deleted, as it's only used the first time you boot the machine.</p>
<center> 
<iframe width="560" height="315" src="https://www.youtube.com/embed/jhbkTQ9yA-4" frameborder="0" allowfullscreen></iframe>
</center>
</div>

<h2>Access Wordpress</h2>

<div class="information">
<p>Use one of the following addresses, HTTPS is preffered:
<h3>
<ul>
 <li><a href="http://<?=$_SERVER['SERVER_NAME'];?>/wp-admin/options-general.php"        >http://<?=$_SERVER['SERVER_NAME'];?></a> (HTTP)
 <li><a href="https://<?=$_SERVER['SERVER_NAME'];?>/wp-admin/options-general.php"             >https://<?=$_SERVER['SERVER_NAME'];?></a> (HTTPS)
 <p>
 </ul>
</h3>
<p>Note: Please accept the warning in the browser if you connect via HTTPS. It is recomended
<br> to <a href="https://www.techandme.se/publish-your-server-online" target="_blank">buy your own certificate and replace the self-signed certificate to your own.</a>
<br>
<p>Note: Before you can login you have to run the setup script, as descirbed in the video above.
</div>

<h2>Access Webmin</h2>

<div class="information">
<p>Use one of the following addresses, HTTPS is preffered:
<h3>
<ul>
 <li><a href="http://<?=$_SERVER['SERVER_NAME'];?>:10000"        >http://<?=$_SERVER['SERVER_NAME'];?></a> (HTTP)
 <li><a href="https://<?=$_SERVER['SERVER_NAME'];?>:10000"             >https://<?=$_SERVER['SERVER_NAME'];?></a> (HTTPS)
 <p>
 </ul>
</h3>
<p>Note: Please accept the warning in the browser if you connect via HTTPS.</p>
<h3>
<a href="https://www.techandme.se/user-and-password/" target="_blank">Login details</a>
</h3>
<p> Note: Webmin is installed when you run the setup script. To access Webmin externally you have to open port 10000 in your router.</p>
</div>

<h2>Access Adminer</h2>

<div class="information">
<p>Use one of the following addresses, HTTPS is preffered:
<h3>
<ul>
 <li><a href="http://<?=$_SERVER['SERVER_NAME'];?>:81"        >http://<?=$_SERVER['SERVER_NAME'];?></a> (HTTP)
 <p>
 </ul>
<a href="https://www.techandme.se/user-pass/" target="_blank">Login details</a>
</h3>
<p>Note: Your external IP is set as approved in /etc/nginx/sites-available/adminer.conf, all other access is forbidden.<p/>
</div>
