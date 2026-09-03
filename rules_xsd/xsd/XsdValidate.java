package dev.fastverk.xsd;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.transform.stream.StreamSource;
import javax.xml.validation.Schema;
import javax.xml.validation.SchemaFactory;
import javax.xml.validation.Validator;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;
import org.xml.sax.ErrorHandler;
import org.xml.sax.SAXParseException;

/**
 * Generic, offline XSD validator — the reusable core of the future {@code
 * rules_xsd} ruleset. Validates an XML instance against a schema whose {@code
 * <xsd:import>}/{@code <xsd:include>}s are resolved entirely from a declared
 * local closure, so validation never touches the network even when the schema's
 * {@code schemaLocation}s are absolute remote URLs (as USLM-1.0's are).
 *
 * <p>Pure JDK: validation runs the JDK's bundled Apache Xerces
 * ({@code javax.xml.validation}); import resolution uses the standard
 * {@code javax.xml.catalog.CatalogResolver}. The catalog is built on the fly by
 * scanning each closure schema's imports and mapping every {@code schemaLocation}
 * to the local file whose {@code targetNamespace} matches — no domain knowledge,
 * no hardcoded URLs.
 *
 * <p>Args: {@code --root=<entry.xsd> --xml=<instance.xml>
 * --closure=<a.xsd,b.xsd,...>}. Exit 0 iff valid; 1 on validation error;
 * 2 on usage/IO error.
 */
public final class XsdValidate {

  public static void main(String[] args) throws Exception {
    String root = null;
    String xml = null;
    String closure = "";
    for (String a : args) {
      if (a.startsWith("--root=")) {
        root = a.substring("--root=".length());
      } else if (a.startsWith("--xml=")) {
        xml = a.substring("--xml=".length());
      } else if (a.startsWith("--closure=")) {
        closure = a.substring("--closure=".length());
      } else {
        System.err.println("xsd_validate: unknown arg: " + a);
        System.exit(2);
      }
    }
    if (root == null || xml == null) {
      System.err.println("usage: XsdValidate --root=<xsd> --xml=<xml> --closure=<csv>");
      System.exit(2);
    }

    List<File> closureFiles = new ArrayList<>();
    for (String path : closure.split(",")) {
      if (!path.isEmpty()) {
        closureFiles.add(new File(path));
      }
    }

    // Build an OASIS XML Catalog mapping each import's schemaLocation to the
    // local closure file, and drive resolution through the native JAXP 1.6
    // catalog feature (USE_CATALOG) — which Xerces honors for *all* schema
    // imports, unlike setResourceResolver, which it skips for the built-in XML
    // namespace. RESOLVE=ignore: an unmatched reference (notably the W3C
    // XMLSchema.dtd that xml.xsd declares but doesn't depend on) resolves to an
    // empty source rather than throwing or hitting the network — fully offline.
    Path catalog = buildCatalog(closureFiles);
    String catalogUri = catalog.toUri().toString();

    List<String> errors = new ArrayList<>();
    ErrorHandler collector =
        new ErrorHandler() {
          @Override
          public void warning(SAXParseException e) {
            /* warnings don't fail the gate */
          }

          @Override
          public void error(SAXParseException e) {
            errors.add(format(e));
          }

          @Override
          public void fatalError(SAXParseException e) {
            errors.add(format(e));
          }
        };

    try {
      SchemaFactory factory = SchemaFactory.newInstance(XMLConstants.W3C_XML_SCHEMA_NS_URI);
      factory.setFeature(XMLConstants.USE_CATALOG, true);
      factory.setProperty("javax.xml.catalog.files", catalogUri);
      factory.setProperty("javax.xml.catalog.resolve", "ignore");
      factory.setProperty(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "file");
      factory.setErrorHandler(collector);
      Schema schema = factory.newSchema(new StreamSource(sanitizeDoctype(new File(root))));

      Validator validator = schema.newValidator();
      validator.setFeature(XMLConstants.USE_CATALOG, true);
      validator.setProperty("javax.xml.catalog.files", catalogUri);
      validator.setProperty("javax.xml.catalog.resolve", "ignore");
      validator.setErrorHandler(collector);
      validator.validate(new StreamSource(new File(xml)));
    } catch (Exception e) {
      System.err.println(
          "xsd_validate: " + e.getClass().getSimpleName() + ": " + e.getMessage());
      System.exit(errors.isEmpty() ? 2 : 1);
    }

    if (!errors.isEmpty()) {
      System.err.println("xsd_validate: " + errors.size() + " validation error(s):");
      for (String e : errors) {
        System.err.println("  " + e);
      }
      System.exit(1);
    }
    System.out.println(
        "xsd_validate: OK (" + new File(xml).getName() + " conforms to "
            + new File(root).getName() + ")");
  }

  private static String format(SAXParseException e) {
    return "line " + e.getLineNumber() + " col " + e.getColumnNumber() + ": " + e.getMessage();
  }

  /**
   * Serve a DOCTYPE-free copy of a schema. A vestigial external-DTD reference
   * (e.g. the W3C xml.xsd's {@code <!DOCTYPE ... "XMLSchema.dtd">}) would
   * otherwise make the schema parser load an offline-unresolvable DTD and drop
   * the schema's declarations (so xml:base/xml:lang never register). Returns the
   * original file when it has no DOCTYPE.
   */
  static File sanitizeDoctype(File f) throws Exception {
    String content = new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8);
    int i = content.indexOf("<!DOCTYPE");
    if (i < 0) {
      return f;
    }
    int bracket = content.indexOf('[', i);
    int gt = content.indexOf('>', i);
    int end = (bracket >= 0 && bracket < gt)
        ? content.indexOf('>', content.indexOf(']', bracket)) // internal subset
        : gt;
    String stripped = content.substring(0, i) + content.substring(end + 1);
    Path tmp = Files.createTempFile("xsd-nodoctype-", "-" + f.getName());
    tmp.toFile().deleteOnExit();
    Files.write(tmp, stripped.getBytes(StandardCharsets.UTF_8));
    return tmp.toFile();
  }

  /**
   * Generate a temp XML catalog mapping every import/include schemaLocation in
   * the closure to its local file (imports matched by targetNamespace, includes
   * by filename). Returns the catalog file path.
   */
  private static Path buildCatalog(List<File> closureFiles) throws Exception {
    Map<String, File> byNamespace = new HashMap<>();
    Map<String, File> byBasename = new HashMap<>();
    for (File f : closureFiles) {
      File served = sanitizeDoctype(f); // serve a DOCTYPE-free copy (see sanitizeDoctype)
      byBasename.put(f.getName(), served);
      String ns = readTargetNamespace(f);
      if (ns != null && !ns.isEmpty()) {
        byNamespace.putIfAbsent(ns, served);
      }
    }

    // schemaLocation (as written in the schema) -> local file to serve.
    Map<String, File> locationToFile = new LinkedHashMap<>();
    for (File f : closureFiles) {
      for (Reference ref : scanReferences(f)) {
        if (ref.schemaLocation == null || ref.schemaLocation.isEmpty()) {
          continue;
        }
        File target = null;
        if (ref.namespace != null && byNamespace.containsKey(ref.namespace)) {
          target = byNamespace.get(ref.namespace); // <import>
        } else {
          target = byBasename.get(new File(ref.schemaLocation).getName()); // <include>
        }
        if (target != null) {
          locationToFile.putIfAbsent(ref.schemaLocation, target);
        }
      }
    }

    StringBuilder sb = new StringBuilder();
    sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    sb.append("<catalog xmlns=\"urn:oasis:names:tc:entity:xmlns:xml:catalog\">\n");
    for (Map.Entry<String, File> e : locationToFile.entrySet()) {
      String loc = xmlAttr(e.getKey());
      String uri = xmlAttr(e.getValue().toURI().toString());
      sb.append("  <system systemId=\"").append(loc).append("\" uri=\"").append(uri).append("\"/>\n");
      sb.append("  <uri name=\"").append(loc).append("\" uri=\"").append(uri).append("\"/>\n");
    }
    sb.append("</catalog>\n");

    if (System.getenv("XSD_DEBUG_CATALOG") != null) {
      System.err.println("---- catalog ----\n" + sb + "-----------------");
    }
    Path catalog = Files.createTempFile("xsd-closure-", ".catalog.xml");
    catalog.toFile().deleteOnExit();
    Files.write(catalog, sb.toString().getBytes(StandardCharsets.UTF_8));
    return catalog;
  }

  private static String xmlAttr(String s) {
    return s.replace("&", "&amp;").replace("\"", "&quot;").replace("<", "&lt;");
  }

  /** An {@code <xsd:import>}/{@code <xsd:include>} reference found in a schema. */
  private static final class Reference {
    final String namespace; // null for <include>
    final String schemaLocation;

    Reference(String namespace, String schemaLocation) {
      this.namespace = namespace;
      this.schemaLocation = schemaLocation;
    }
  }

  /** Scan a schema for its {@code import}/{@code include} references (DOM). */
  private static List<Reference> scanReferences(File f) {
    List<Reference> refs = new ArrayList<>();
    Document doc = parseXsd(f);
    if (doc == null) {
      return refs;
    }
    for (String tag : new String[] {"import", "include"}) {
      NodeList nl = doc.getElementsByTagNameNS(XSD_NS, tag);
      for (int i = 0; i < nl.getLength(); i++) {
        Element e = (Element) nl.item(i);
        refs.add(new Reference(
            e.hasAttribute("namespace") ? e.getAttribute("namespace") : null,
            e.getAttribute("schemaLocation")));
      }
    }
    return refs;
  }

  /** Read a schema's {@code targetNamespace} (DOM). */
  private static String readTargetNamespace(File f) {
    Document doc = parseXsd(f);
    return doc == null ? null : doc.getDocumentElement().getAttribute("targetNamespace");
  }

  /**
   * Parse a schema as XML with external-DTD loading disabled, so a DOCTYPE
   * (xml.xsd declares one referencing the W3C XMLSchema.dtd) is tolerated and
   * never fetched. Returns null if the file can't be parsed.
   */
  private static Document parseXsd(File f) {
    try {
      DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
      dbf.setNamespaceAware(true);
      dbf.setValidating(false);
      dbf.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false);
      dbf.setFeature("http://xml.org/sax/features/external-general-entities", false);
      dbf.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
      return dbf.newDocumentBuilder().parse(f);
    } catch (Exception e) {
      return null;
    }
  }

  private static final String XSD_NS = "http://www.w3.org/2001/XMLSchema";

  private XsdValidate() {}
}
