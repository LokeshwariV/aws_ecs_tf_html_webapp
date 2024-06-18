data "aws_instance" "nginx" {
  filter {
    name   = "tag:Name"
    values = ["nginx-instance"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

resource "null_resource" "deploy_nginx" {
  provisioner "remote-exec" {
    inline = [
      "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 901407365530.dkr.ecr.us-east-1.amazonaws.com/hello_world_html",
      "docker pull 901407365530.dkr.ecr.us-east-1.amazonaws.com/hello_world_html:latest",
      "docker run -d -p 80:80 --name nginx 901407365530.dkr.ecr.us-east-1.amazonaws.com/hello_world_html:latest"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${path.module}/deployer-key.pem")
      host        = data.aws_instance.nginx.public_ip
    }
  }

  depends_on = [data.aws_instance.nginx]
}
