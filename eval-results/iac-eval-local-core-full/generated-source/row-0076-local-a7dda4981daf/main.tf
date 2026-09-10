terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "kendra" {
  name = "iac-eval-kendra-index-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kendra.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "kendra" {
  name = "iac-eval-kendra-index-policy"
  role = aws_iam_role.kendra.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kendra_index" "default" {
  name     = "iac-eval-basic-kendra-index"
  edition  = "DEVELOPER_EDITION"
  role_arn = aws_iam_role.kendra.arn

  document_metadata_configuration_updates {
    name = "_authors"
    type = "STRING_LIST_VALUE"

    search {
      displayable = true
      facetable   = true
      searchable  = true
      sortable    = false
    }
  }

  document_metadata_configuration_updates {
    name = "_category"
    type = "STRING_VALUE"

    search {
      displayable = true
      facetable   = true
      searchable  = true
      sortable    = true
    }
  }

  document_metadata_configuration_updates {
    name = "_created_at"
    type = "DATE_VALUE"

    search {
      displayable = true
      facetable   = true
      searchable  = false
      sortable    = true
    }
  }

  document_metadata_configuration_updates {
    name = "_data_source_id"
    type = "STRING_VALUE"

    search {
      displayable = true
      facetable   = true
      searchable  = true
      sortable    = true
    }
  }

  document_metadata_configuration_updates {
    name = "_document_body"
    type = "STRING_VALUE"

    search {
      displayable = true
      facetable   = false
      searchable  = true
      sortable    = false
    }
  }

  document_metadata_configuration_updates {
    name = "_document_id"
    type = "STRING_VALUE"

    search {
      displayable = true
      facetable   = true
      searchable  = true
      sortable    = true
    }
  }

  document_metadata_configuration_updates {
    name = "_excerpt_page_number"
    type = "LONG_VALUE"

    search {
      displayable = true
      facetable   = false
      searchable  = false
      sortable    = false
    }
  }

  document_metadata_configuration_updates {
    name = "_faq_id"
    type = "STRING_VALUE"

    search {
      displayable = true
      facetable   = true
      searchable  = true
      sortable    = true
    }
  }

  document_metadata_configuration_updates {
    name = "_file_type"
    type = "STRING_VALUE"

    search {
      displayable = true
      facetable   = true
      searchable  = true
      sortable    = true
    }
  }

  document_metadata_configuration_updates {
    name = "_language_code"
    type = "STRING_VALUE"

    search {
      displayable = true
      facetable   = true
      searchable  = true
      sortable    = true
    }
  }

  document_metadata_configuration_updates {
    name = "_last_updated_at"
    type = "DATE_VALUE"

    search {
      displayable = true
      facetable   = true
      searchable  = false
      sortable    = true
    }
  }

  document_metadata_configuration_updates {
    name = "_source_uri"
    type = "STRING_VALUE"

    search {
      displayable = true
      facetable   = false
      searchable  = true
      sortable    = false
    }
  }

  document_metadata_configuration_updates {
    name = "_version"
    type = "STRING_VALUE"

    search {
      displayable = true
      facetable   = true
      searchable  = true
      sortable    = true
    }
  }
}
