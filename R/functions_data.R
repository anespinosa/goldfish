################################## ###
#
# Goldfish package
#
# Functions related to the creation of data objects
#
################################## ###

## INTERFACE objects

#' Create a data frame from a dynamic nodes object
#' @param x a goldfish nodes object
#' @param time a numeric or time format to define the state of the nodes object at time - epsiolon
#' @param startTime a numeric or time format; prior events are disregarded
#' @param ... additional arguments to be passed to or from methods
#' @export
#' @return a data frame
as.data.frame.nodes.goldfish <- function(x, time = -Inf, startTime = -Inf, envir = environment(), ...) {
  df <- x
  dynamicAttributes <- attr(df, "dynamicAttribute")
  eventNames <- attr(df, "events")
  if (is.character(time)) time <- as.POSIXct(time)
  time <- as.numeric(time)
  startTime <- as.numeric(startTime)
  if (length(eventNames) == 0) {
    return(df)
  }
  for (i in seq_along(eventNames)) {
    events <- get(eventNames[i], envir = envir)
    events <- sanitizeEvents(events, df, envir = envir)
    events <- events[events$time >= startTime & events$time < time, ]

    if (nrow(events) > 0 && !is.null(events$replace)) {
      df[[dynamicAttributes[i]]][events$node] <- events$replace
    }
    if (nrow(events) > 0 && !is.null(events$increment)) {
      for (k in seq_len(nrow(events))) {
        oldValue <- df[[dynamicAttributes[i]]][events[k, ]$node]
        df[[dynamicAttributes[i]]][events[k, ]$node] <- oldValue + events[k, ]$increment
      }
    }
  }
  df
}

#' Create a Matrix from a dynamic nodes object
#' @param x a dynamic goldfish network object
#' @param time a numeric or time format to define the state of the nodes object at time - epsiolon
#' @param startTime a numeric or time format; prior events are disregarded
#' @param ... additional arguments to be passed to or from methods
#' @export
#' @return a matrix
as.matrix.network.goldfish <- function(x, time = -Inf, startTime = -Inf, envir = environment(),  ...) {
  net <- x
  if (is.character(time)) time <- as.POSIXct(time)
  time <- as.numeric(time)
  startTime <- as.numeric(startTime)
  dim <- dim(net)
  useLoop <- F
  isDirected <- attr(net, "directed")
  eventNames <- attr(net, "events")
  nodeNames <- attr(net, "nodes")
  nodes <- nodeNames[1]
  nodes2 <- nodes
  if (length(nodeNames) == 2) {
    nodes2 <- nodeNames[2]
  }
  if (is.null(eventNames)) {
    return(x[1:dim[1], 1:dim[2]])
  }
  events <- lapply(lapply(eventNames, get, envir = envir),
    sanitizeEvents,
    nodes = nodes, nodes2 = nodes2, envir = envir
  )
  # quick update for single event lists with replace
  if (length(events) == 1) {
    df <- events[[1]][events[[1]]$time < time & events[[1]]$time >= startTime, ]
    if (nrow(df) > 0) {
      if (!is.null(df$increment)) {
        useLoop <- T
      }
      if (!is.null(df$replace)) {
        net[cbind(df$sender, df$receiver)] <- df$replace
        if (!isDirected) {
          net[cbind(df$receiver, df$sender)] <- df$replace
        }
      }
    }
  }
  if (length(events) > 1 || useLoop) {
    times <- sort(unique(unlist(lapply(events, getElement, "time"))))
    times <- times[times < time & times >= startTime]
    # update loop
    for (t in times) {
      for (i in seq_len(length(events))) {
        df <- events[[i]][events[[i]]$time == t, ]
        if (nrow(df) > 0) {
          if (!is.null(df$replace)) {
            net[cbind(df$sender, df$receiver)] <- df$replace
          }
          if (!is.null(df$increment)) {
            net[cbind(df$sender, df$receiver)] <-
              df$increment + net[cbind(df$sender, df$receiver)]
            if (!isDirected) {
              net[cbind(df$receiver, df$sender)] <-
                df$increment + net[cbind(df$receiver, df$sender)]
            }
          }
        }
      }
    }
  }

  return(net[1:dim[1], 1:dim[2]])
}

#' Return details about any goldfish objects in a given list
#' @param y a list of objects. Leave blank to capture the global environment.
#' @return classes, dimensions, and any related nodesets or events
#' for any goldfish objects in a given list.
#' @export
#' @examples
#' goldfishObjects()
goldfishObjects <- function(y = ls(envir = .GlobalEnv), envir = .GlobalEnv) {
  tryCatch({
    # identify goldfish objects
    classesToKeep <- c("nodes.goldfish", "network.goldfish", "dependent.goldfish",
                       "global.goldfish")
    ClassFilter <- function(x) any(checkClasses(get(x, envir = envir), classes = classesToKeep))
    object <- Filter(ClassFilter, y)
    # if(is.null(object)) stop("No goldfish objects defined.")

    # identify classes of these objects
    classes <- vapply(object,
                      FUN = function(x) checkClasses(get(x, envir = envir), classes = classesToKeep),
                      FUN.VALUE = logical(length(classesToKeep)))

    if (any(classes["nodes.goldfish", ])) {
      cat("Goldfish Nodes\n")
      names <- object[classes["nodes.goldfish", ]]
      n <- vapply(names, function(x) nrow(get(x, envir = envir)), integer(1))
      attributes <- vapply(names, function(x) paste(names(get(x, envir = envir)), collapse = ", "), character(1))
      events <- vapply(names,
                       function(x) paste(attr(get(x, envir = envir), "dynamicAttributes"), collapse = ", "),
                       character(1))
      print(data.frame(row.names = names, n, attributes, events))
      cat("\n")
    }

    if (any(classes["network.goldfish", ])) {
      cat("Goldfish Networks\n")
      names <- object[classes["network.goldfish", ]]
      dimensions <- vapply(names,
                           function(x) paste(dim(get(x, envir = envir)), collapse = " x "),
                           character(1))
      nodesets <- vapply(names,
                         function(x) paste(attr(get(x, envir = envir), "nodes"), collapse = ", "),
                         character(1))
      events <- vapply(names,
                       function(x) paste(attr(get(x, envir = envir), "events"), collapse = ", "),
                       character(1))
      print(data.frame(row.names = names, dimensions, nodesets, events))
      cat("\n")
    }

    if (any(classes["dependent.goldfish", ])) {
      cat("Goldfish Dependent Events\n")
      names <- object[classes["dependent.goldfish", ]]
      n <- vapply(names, function(x) nrow(get(x, envir = envir)), integer(1))
      network <- vapply(names,
                        function(x) {
                          net <- attr(get(x, envir = envir), "defaultNetwork")
                          ifelse(is.null(net), "", net)
                          },
                        character(1))
      print(data.frame(row.names = names, n, network))
      cat("\n")
    }

    if (any(classes["global.goldfish", ])) {
      cat("Goldfish Global Attributes\n")
      names <- object[classes["global.goldfish", ]]
      dimensions <- vapply(names, function(x) nrow(get(x, envir = envir)), integer(1))
      print(data.frame(row.names = names, dimensions))
      cat("\n")
    }
  }, error = function(e) return(NULL))
}

## DEFINE objects

#' Defining a node set with (dynamic) node attributes.
#'
#' The \code{defineNodes} function processes and checks the \code{\link{data.frame}} passed to \code{nodes} argument.
#' This is a necessary step before the definition of the network.
#'
#' Additional columns in the \code{nodes} argument are considered as the initial values of nodes attributes.
#' Those columns must be of class \code{\link{numeric}}, \code{\link{character}}, \code{\link{logical}}
#'
#' @param nodes \code{\link{data.frame}} that contains
#' \describe{
#'  \item{label}{\code{\link{character}} column containing the nodes labels (mandatory)}
#'  \item{present}{\code{\link{logical}} column indicating if the respective node is present at the
#'  first timepoint (optional)}
#' }
#'
#' @return an object of class \code{nodes.goldfish}
#' @export
#' @seealso \link{defineNetwork}
#' @examples
#' nodesAttr <- data.frame(
#'   label = paste("Actor", 1:5),
#'   present = c(TRUE, FALSE, TRUE, TRUE, FALSE),
#'   gender = c(1, 2, 1, 1, 2)
#'   )
#' nodesAttr <- defineNodes(nodes = nodesAttr)
#'
#' # Social evolution nodes definition
#' data("Social_Evolution")
#' actors <- defineNodes(actors)
#'
#' # Fisheries treaties nodes definition
#' data("Fisheries_Treaties_6070")
#' states <- defineNodes(states)
defineNodes <- function(nodes) {
  # check input types
  if (!is.data.frame(nodes)) stop("Invalid argument: this function expects a data frame.")
  # define class
  class(nodes) <- unique(c("nodes.goldfish", class(nodes)))
  # create events attribute
  attr(nodes, "events") <- vector("character")
  attr(nodes, "dynamicAttributes") <- vector("character")
  # check format
  tryCatch(checkNodes(nodes), error = function(e) {
    scalls <- sys.calls()
    e$call <- scalls[[1]]
    nodes <- NA
    e$message <- paste("The nodeset couldn't be constructed: ", e$message)
    stop(e)
  })
  return(nodes)
}

#' Defining a network with dynamic events
#'
#' Once the \code{nodeset} is defined, the \code{defineNetwork} function defines a network object either from
#' a node-set or from a sociomatrix. If a sociomatrix or adjacency matrix is used as input,
#' \code{defineNetwork} returns a static Network. If the node-set only is used as input,
#' \code{defineNetwork} returns an empty network. From there, a dynamic network can be constructed by
#' linking dynamic events to the network object.
#'
#' @param matrix An initial matrix (optional)
#' @param nodes A node-set (\code{nodes.goldfish} object)
#' @param nodes2 A second optional node-set for the definition of two-mode networks
#' @param directed A logical value indicating whether the network is directed
#' @export
#' @return an object of class network.goldfish
#' @details If a sociomatrix is used as input, \code{defineNetwork} returns a static Network.
#' This matrix must contain the same nodeset as defined with the \code{defineNodes} function
#' and the order of the rows and columns must correspond to the order of node lables in the node-set.
#' The matrix must be binary (if unweighted?) and
#' can be directed or undirected (as specified with the directed argument).
#' If this network is updated over time (e.g., a new wave of friendship data is collected),
#' these changes can be added with the \link{linkEvents} function - similar to link changing
#' attribute events to a nodeset. This time, the user needs to provide the network and the associated nodeset.
#' If no matrix is provided, goldfish only considers the nodeset and assumes
#' the initial state to be empty (i.e., a matrix containing only 0s). For the network to become dynamic,
#' the adjacency matrix or the nodeset can be linked to a dynamic event-list data.frame in the initial state or
#' empty network object by using the function \link{linkEvents}.
#'
#' @seealso \link{defineNodes} \link{linkEvents}
#' @importFrom methods is
#' @examples
#' # If no matrix is provided
#' data("Social_Evolution")
#' callNetwork <- defineNetwork(nodes = actors)
#'
#' # If a sociomatrix is provided
#' data("Fisheries_Treaties_6070")
#' bilatnet <- defineNetwork(bilatnet, nodes = states, directed = FALSE)
defineNetwork <- function(matrix = NULL, nodes, nodes2 = NULL, directed = TRUE) {

  # check input types
  isTwoMode <- !is.null(nodes2)
  nRow <- nrow(nodes)
  nCol <- ifelse(isTwoMode, nrow(nodes2), nrow(nodes))

  if (!any(checkClasses(nodes, c("data.frame", "nodes.goldfish")))) {
    stop("Invalid argument nodes: this function expects a dataframe or a nodes.goldfish object.")
  }
  if (!is.null(nodes2) && !any(checkClasses(nodes2, c("data.frame", "nodes.goldfish")))) {
    stop("Invalid argument nodes2: this function expects a dataframe or a nodes.goldfish object.")
  }
  if (!is.logical(directed)) {
    stop("Invalid argument directed: this function expects a boolean.")
  }

  # Create empty matrix if needed
  # TODO: Consider a sparse representation
  if (is.null(matrix)) {
      matrix <- matrix(0, nRow, nCol,
                       dimnames = list(sender = nodes$label,
                                       receiver = if (isTwoMode) nodes2$label else nodes$label))
  } else if (is.table(matrix)) {
    if (length(dim(matrix)) != 2) stop('"matrix" object has an incorrect number of dimensions. Expected 2 dimensions')
    matrix <- structure(matrix, class = NULL, call = NULL)
  } else if (!any(checkClasses(matrix, c("matrix", "Matrix")))) {
    stop('Invalid argument "matrix": this function expects a matrix.')
  } #else if ()

  # define class
  class(matrix) <- unique(c("network.goldfish", class(matrix)))

  # create attributes
  attr(matrix, "events") <- vector("character")
  # if (isTwoMode) {
    nodesName <- c(as.character(substitute(nodes)), as.character(substitute(nodes2)))
  # } else {
  #   nodesName <- as.character(substitute(nodes))
  # }
  attr(matrix, "nodes") <- nodesName
  attr(matrix, "directed") <- directed

  # check format
  tryCatch(checkNetwork(matrix, nodes, nodesName, nodes2 = nodes2),
    error = function(e) {
      scalls <- sys.calls()
      e$call <- scalls[[1]]
      e$message <- paste("The network couldn't be constructed: ", e$message)
      matrix <- NA
      stop(e)
    }
  )

  return(matrix)
}

#' Define dependent events for a model
#'
#' The final step in defining the data objects is to identify the dependent events.
#'
#' @param events a data frame containing the event list that should be considered as a dependent variable in models.
#' @param nodes a data frame or a nodes.goldfish object containing the nodes used in the event list
#' @param nodes2 a second nodeset in the case of two mode events
#' @param defaultNetwork the name of a goldfish network object
#' @return an object of class dependent.goldfish
#' @export
#' @details Before this step is performed, we have to define: 1. the nodeset (defineNodes), the network (defineNetwork)
#'  and the eventlist of the network (linkEvents).
#' @seealso \link{defineNodes} \link{defineNetwork} \link{linkEvents}
#' @examples
#' actors <- data.frame(
#'   actor = 1:5, label = paste("Actor", 1:5),
#'   present = TRUE, gender = sample.int(2, 5, replace = TRUE)
#' )
#' actors <- defineNodes(nodes = actors)
#' calls <- data.frame(
#'   time = c(12, 27, 45, 56, 66, 68, 87), sender = paste("Actor", c(1, 3, 5, 2, 3, 4, 2)),
#'   receiver = paste("Actor", c(4, 2, 3, 5, 1, 2, 5)), increment = rep(1, 7)
#' )
#' callNetwork <- defineNetwork(nodes = actors)
#' callNetwork <- linkEvents(x = callNetwork, changeEvent = calls, nodes = actors)
#'
#' # Defining the dependent events:
#' callDependent <- defineDependentEvents(events = calls, nodes = actors, defaultNetwork = callNetwork)
defineDependentEvents <- function(events, nodes, nodes2 = NULL, defaultNetwork = NULL) {
  # check input types
  isTwoMode <- !is.null(nodes2)
  if (!is.data.frame(events)) stop("Invalid argument events: this function expects a data frame.")
  if (!is.data.frame(nodes))
    stop("Invalid argument nodes: this function expects a data frame or a nodes.goldfish object.")
  if (isTwoMode && !is.data.frame(nodes2))
    stop("Invalid argument nodes2: this function expects a data frame or a nodes.goldfish object.")
  if (!is.null(defaultNetwork) && !inherits(defaultNetwork, "network.goldfish"))
    stop("Invalid argument defaultNetwork: this function expects a network.goldfish object.")

  # link objects
  depEnvir <- environment()
  nodesName <- c(as.character(substitute(nodes, depEnvir)), as.character(substitute(nodes2, depEnvir)))
  objEvents <- as.character(substitute(events, depEnvir))
  objDefNet <- as.character(substitute(defaultNetwork, depEnvir))

  attr(events, "nodes") <- nodesName

  # define class
  class(events) <- unique(c("dependent.goldfish", class(events)))

  # link events if defaultNetwork
  if (!is.null(defaultNetwork)) {
    if (!all(attr(defaultNetwork, "nodes") == nodesName)) {
      stop("Node sets of default networks differ from node sets of dependent variable")
    }
    attr(events, "defaultNetwork") <- objDefNet
    attr(events, "type") <- "dyadic"
    # check defaultNetwork is defined with the same events
    if (!any(objEvents %in% attr(defaultNetwork, "events")))
      warning("The events are not linked to the defaultNetwork.",
              "\nEvents attached to the \"defaultNetwork\": ", paste(attr(defaultNetwork, "events"), collapse = ", "),
              "\nDependent events: ", paste(objEvents, collapse = ""),
              "\n")
  } else attr(events, "type") <- "monadic"

  # check format
  # TODO: removed defaultNetwork from check
  tryCatch(
    checkDependentEvents(
      events = events, eventsName = objEvents,
      nodes = nodes, nodes2 = nodes2,
      defaultNetwork = defaultNetwork, environment = depEnvir),
    error = function(e) {
      scalls <- sys.calls()
      e$call <- scalls[[1]]
      e$message <- paste("The dependent events couldn't be constructed: ", e$message)
      # events <- NA
      stop(e)
    })

  return(events)
}


#' Define a global time-varying attribute
#'
#' This function allows to define a global attribute of the nodeset (i.e a variable that is identical for each node
#' but changes over time).
#'
#' @param global a data frame containing all the values this global attribute takes along time
#' @return an object of class global.goldfish
#' @export
#' @details  For instance, seasonal climate changes could be defined as a changing global attribute. Then,
#' this global attribute can be linked to the nodeset by using \link{linkEvents}
#' @examples
#' seasons <- defineGlobalAttribute(data.frame(time = 1:12, replace = 1:12))
defineGlobalAttribute <- function(global) {
  # check input types
  if (!is.data.frame(global)) stop("Invalid argument: this function expects a data frame.")

  # define class
  class(global) <- unique(c("global.goldfish", class(global)))

  # check format
  tryCatch(
    checkGlobalAttribute(global),
    error = function(e) {
      scalls <- sys.calls()
      e$call <- scalls[[1]]
      e$message <- paste("The global attribute couldn't be constructed: ", e$message)
      # global <- NA
      stop(e)
    })

  return(global)
}


#' Attach dynamic events to a nodeset or a network
#' @param x Either a nodeset (nodes.goldfish object) or a network
#'   (network.goldfish object)
#' @param changeEvents The name of a dataframe that represents a valid events list
#' @param attribute a character vector indicating the names of the attributes
#'   that should be updated by the specified events (ONLY if the object is a
#'   nodeset)
#' @param nodes a nodeset (dataframe or nodes.goldfish object) related to the
#'   network (ONLY if the object is a network)
#' @param nodes2 an optional nodest (dataframe or nodes.goldfish object) related
#'   to the network (ONLY if object is a network)
#' @return an object of class nodes.goldfish or network.goldfish
#' @export linkEvents
#' @seealso \link{defineNodes} \link{defineNetwork}
#' @examples
#' actors <- data.frame(
#'   actor = 1:5, label = paste("Actor", 1:5),
#'   present = TRUE, gender = sample.int(2, 5, replace = TRUE)
#' )
#' actors <- defineNodes(nodes = actors)
#' callNetwork <- defineNetwork(nodes = actors)
#'
#' # Link events to a Nodeset
#' compositionChangeEvents <- data.frame(time = c(14, 60), node = "Actor 4", replace = c(FALSE, TRUE))
#' actorsnew <- linkEvents(x = actors, attribute = "present", changeEvents = compositionChangeEvents)
#'
#' # Link events to a Network
#' calls <- data.frame(
#'   time = c(12, 27, 45, 56, 66, 68, 87), sender = paste("Actor", c(1, 3, 5, 2, 3, 4, 2)),
#'   receiver = paste("Actor", c(4, 2, 3, 5, 1, 2, 5)), increment = rep(1, 7)
#' )
#' callNetwork <- linkEvents(x = callNetwork, changeEvent = calls, nodes = actors)
linkEvents <- function(x, changeEvents, ...)
  UseMethod("linkEvents", x)

#' @rdname linkEvents
#' @export
linkEvents.nodes.goldfish <- function(x, changeEvents, attribute) {
  # check input types
  if (!(is.character(attribute) && length(attribute) == 1))
    stop("Invalid argument attributes: this function expects a character attribute value.")
  if (!is.data.frame(changeEvents)) stop("Invalid argument changeEvents: this function expects a data frame.")

  # data frame has to be passed as a variable name
  linkEnvir <- environment()
  if (!is.name(substitute(changeEvents, linkEnvir)))
    stop("Parameter change events has to be the name of a data frame (rather than a data frame)")

  # link data
  # initial <- object
  objEventsPrev <- attr(x, "events")
  objEventCurr <- as.character(substitute(changeEvents, linkEnvir))

  if (length(objEventsPrev) > 0 && objEventCurr %in% objEventsPrev) {
      warning("The event ", sQuote(objEventCurr), " were already linked to this object.")
      return(x)
  }

  attr(x, "events") <- c(objEventsPrev, objEventCurr)
  attr(x, "dynamicAttributes") <- c(attr(x, "dynamicAttributes"), attribute)

  # check format
  tryCatch({
    checkEvents(object = x, events = changeEvents, eventsName = objEventCurr,
                attribute = attribute, environment = linkEnvir)
  }, error = function(e) {
    scalls <- sys.calls()
    e$call <- scalls[[1]]
    e$message <- paste("The events couldn't be added: ", e$message)
    # object <- initial
    stop(e)
  })

  return(x)
}

#' @rdname linkEvents
#' @export
linkEvents.network.goldfish <- function(x, changeEvents, nodes = NULL, nodes2 = NULL) {
  # check input types
  if (is.null(nodes)) stop("Invalid argument nodes: a network is specified, this function expects an argument nodes.")
  if (!is.data.frame(changeEvents)) stop("Invalid argument changeEvents: this function expects a data frame.")

  isTwoMode <- !is.null(nodes2)
  if (!is.data.frame(nodes))
    stop("Invalid argument nodes: this function expects a nodeset (data frame or nodes.goldfish object).")
  if (isTwoMode && !is.data.frame(nodes2))
    stop("Invalid argument nodes2: this function expects a nodeset (data frame or nodes.goldfish object).")

  # data frame has to be passed as a variable name
  linkEnvir <- environment()
  if (!is.name(substitute(changeEvents, linkEnvir)))
    stop("Parameter change events has to be the name of a data frame (rather than a data frame)")

  # link data
  # initial <- x
  objEventsPrev <- attr(x, "events")
  objEventCurr <- as.character(substitute(changeEvents, linkEnvir))

  if (length(objEventsPrev) > 0 && objEventCurr %in% objEventsPrev) {
      warning("The event ", sQuote(objEventCurr), " were already linked to this object.")
      return(x)
  }
  attr(x, "events") <- c(objEventsPrev, objEventCurr)

  # check format
  tryCatch({
    checkEvents(object = x, events = changeEvents, eventsName = objEventCurr,
                nodes = nodes, nodes2 = nodes2, environment = linkEnvir)
  }, error = function(e) {
    scalls <- sys.calls()
    e$call <- scalls[[1]]
    e$message <- paste("The events couldn't be added: ", e$message)
    # x <- initial
    stop(e)
  })

  return(x)
}

#' @rdname linkEvents
#' @export
linkEvents.default <- function(x, ...)
  if (!any(checkClasses(x, c("nodes.goldfish", "network.goldfish"))))
    stop('Invalid argument object: this function expects either a "nodes.goldfish" or a "network.goldfish" object.')


createDist2events <- function(network, nodes, nodes2, attribute, FUN, envir = environment()) {
  times <- vector("character")
  if (attribute %in% attr(nodes, "dynamicAttributes")) {
    att.events <- attr(nodes, "events")[which(attr(nodes, "dynamicAttributes") == attribute)]
    att.events <- get(att.events, envir = envir)
    times <- c(times, as.character(unique(att.events$time)))
  }
  if (length(attr(network, "events")) > 0) {
    net.events <- attr(network, "events")
    net.events <- get(net.events, envir = envir)
    times <- c(times, as.character(unique(net.events$time)))
  }
  times <- as.POSIXct(times)

  mat <- vector()
  for (t in times) {
    net <- as.matrix(network, time = t)
    raw <- as.data.frame(nodes, time = t)[, attribute]
    val <- apply(net, 2, function(x) FUN(raw[which(x == 1)], na.rm = TRUE))
    val[is.nan(val)] <- NA
    val[val == -Inf] <- NA
    mat <- rbind(mat, val)
  }

  row.names(mat) <- as.character(times)

  out <- vector()
  for (o in as.character(times)[2:length(times)]) {
    if (!all(mapply(identical, mat[match(o, row.names(mat)), ], mat[match(o, row.names(mat)) - 1, ]))) {
      out <- rbind(
        out,
        data.frame(
          time = o,
          node = nodes2$label[which(!mapply(
            identical,
            mat[match(o, row.names(mat)), ],
            mat[match(o, row.names(mat)) - 1, ]
          ))],
          replace = mat[o, which(!mapply(
            identical,
            mat[match(o, row.names(mat)), ],
            mat[match(o, row.names(mat)) - 1, ]
          ))]
        )
      )
    }
  }
  row.names(out) <- NULL
  out$time <- as.POSIXct(as.character(out$time))
  out$node <- as.character(out$node)
  return(out)
}

# create an initial network for an event list (and node list) and a specific date
createStart <- function(eventlist, nodelist, d) {
  nodes <- nodelist$label
  pre <- eventlist %>%
    filter(sender %in% nodes & receiver %in% nodes) %>%
    filter(time <= d)
  extras <- nodes[(!nodes %in% pre$sender) | (!nodes %in% pre$receiver)]
  pre <- rbind(pre, data.frame(sender = extras, receiver = extras,
                               time = d, increment = 0))
  pre <- as.matrix(table(pre$sender, pre$receiver))
  pre <- pre + t(pre)
  diag(pre) <- 0
  pre
}
