    variable "region" {
        default = "eu-west-2"
    }

    variable "instance_type" {
        default = "t2.micro"
    }

    variable "profile_name" {
        default = "gachio"
    }

    variable "vpc_cidr" {
        default = "178.0.0.0/16"
    }

    variable "uat_public_subnet_cidr" {
        default = "178.0.10.0/24"
    }

    variable "cluster_name" {
        description = "The name to use for all the cluster resources"
        type = string
    }

    variable "db_remote_state_bucket" {
        description = "The name of the S3 bucket for the database's remote state"
        type = string
    }

    variable "db_remote_state_key" {
        description = "The path for the database's remote state in S3"
        type = string
    }