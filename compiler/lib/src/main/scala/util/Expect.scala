package fpp.compiler.util

import scala.reflect.ClassTag

/** Helpers for checking invariants established by earlier compiler passes. */
object Expect {

  /** Return value as T, or report a violated internal compiler invariant. */
  def subtype[T](value: Any)(using tag: ClassTag[T]): T =
    tag.unapply(value) match {
      case Some(value) => value
      case None =>
        val actual = Option(value).fold("null")(_.getClass.getName)
        throw InternalError(s"expected ${tag.runtimeClass.getName}, found $actual")
    }

  /** Return the value of an option known to be nonempty. */
  def some[T](option: Option[T], description: String): T = option match {
    case Some(value) => value
    case None => throw InternalError(s"expected $description")
  }

  /** Split a list known to be nonempty into its head and tail. */
  def nonEmpty[T](list: List[T], description: String): (T, List[T]) = list match {
    case head :: tail => (head, tail)
    case Nil => throw InternalError(s"expected nonempty $description")
  }

}
