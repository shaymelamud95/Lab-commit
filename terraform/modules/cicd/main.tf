#==============================================================================
# CodeCommit Repository
#==============================================================================
resource "aws_codecommit_repository" "app" {
  repository_name = "${var.project_name}-app"
  description     = "Lab-commit application source code"

  tags = {
    Name = "${var.project_name}-app-repo"
  }
}

#==============================================================================
# CodeBuild Project - Build and push Docker images
#==============================================================================
resource "aws_codebuild_project" "frontend" {
  name          = "${var.project_name}-frontend-build"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = "15"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.account_id
    }

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "ECR_REPOSITORY"
      value = var.ecr_frontend_repository_name
    }

    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "app/frontend/buildspec.yml"
  }
}

resource "aws_codebuild_project" "backend" {
  name          = "${var.project_name}-backend-build"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = "15"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.account_id
    }

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "ECR_REPOSITORY"
      value = var.ecr_backend_repository_name
    }

    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "app/backend/buildspec.yml"
  }
}

#==============================================================================
# CodePipeline - Automate build and deploy
#==============================================================================
resource "aws_codepipeline" "app" {
  name     = "${var.project_name}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName       = aws_codecommit_repository.app.repository_name
        BranchName           = "main"
        PollForSourceChanges = false
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "BuildFrontend"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["frontend_output"]

      configuration = {
        ProjectName = aws_codebuild_project.frontend.name
      }
    }

    action {
      name             = "BuildBackend"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["backend_output"]

      configuration = {
        ProjectName = aws_codebuild_project.backend.name
      }

      run_order = 1
    }
  }
}

#==============================================================================
# S3 Bucket for Pipeline Artifacts
#==============================================================================
resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket = "${var.project_name}-pipeline-artifacts-${var.account_id}"

  tags = {
    Name = "${var.project_name}-pipeline-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

#==============================================================================
# EventBridge Rule - Trigger pipeline on CodeCommit push
#==============================================================================
resource "aws_cloudwatch_event_rule" "codecommit_push" {
  name        = "${var.project_name}-codecommit-push"
  description = "Trigger pipeline on CodeCommit push to main branch"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    detail = {
      event          = ["referenceCreated", "referenceUpdated"]
      referenceType  = ["branch"]
      referenceName  = ["main"]
      repositoryName = [aws_codecommit_repository.app.repository_name]
    }
  })
}

resource "aws_cloudwatch_event_target" "codepipeline" {
  rule      = aws_cloudwatch_event_rule.codecommit_push.name
  target_id = "CodePipeline"
  arn       = aws_codepipeline.app.arn
  role_arn  = aws_iam_role.eventbridge.arn
}
