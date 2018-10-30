**app**_farm_ is a tool that lets DevOps teams to manage Java microservice applications spread over multiple hosts(nodes), easily.

It is quite similar to [**cat**_farm_](https://github.com/kumlali/catfarm) project except:

* it supports microservice applications that do not need application server (e.g. Tomcat). 
* it is created for Springboot and Dropwizard applications that do not need an application server (e.g. Tomcat). Can be easily customized for the other frameworks.
* it provides Ant tasks that create domain.

      ant -Ddomain=dev create-domain
