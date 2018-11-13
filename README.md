![](images/logo.png)

**app**_farm_ is a tool that lets DevOps teams to manage Java microservice applications spread over multiple hosts(nodes), easily.

It is quite similar to [**cat**_farm_](https://github.com/kumlali/catfarm) project except:

* it supports microservice applications that do not need application server (e.g. Tomcat). 
* it is created for Springboot and Dropwizard applications and can easily be customized for the other frameworks.
* it provides Ant task to create domain (`create-domain`). That is, you no longer need to create node package(`node.zip`) and install it to all the hosts that the application will run, manually.
  

# Quick Start

* Install supported JDK (HotSpot, IBM or OpenJDK)
* Clone **app**_farm_ project: git clone https://github.com/kumlali/appfarm
* Follow the `CUSTOMIZE: ...` directives in `build.xml` and update them according to your environment.
* Create/update each domain's property file under properties directory. You must have a property file for each domain. (e.g. `dev.properties`, `test.properties`, `qa.properties`, `prod.properties`, etc.)
* Make sure you have key based ssh access from host that runs Ant script to the hosts the application to run.
* Create domain:

      ant -Ddomain=dev create-domain

* Package, deploy and run your application:

      ant -Ddomain=dev -Dversion=myapp-0.0.1-SNAPSHOT create-packs-and-deploy-ha


# Usage

It is almost the same as the [**cat**_farm_](https://github.com/kumlali/catfarm)'s usage.

# Credits

Logo is created with [Photopea](https://www.photopea.com)'s great image editor.
