package dev.fastverk.xsd;

import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.LinkedHashSet;
import java.util.Set;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import org.apache.jena.rdf.model.Model;
import org.apache.jena.rdf.model.ModelFactory;
import org.apache.jena.rdf.model.Resource;
import org.apache.jena.riot.RDFDataMgr;
import org.apache.jena.riot.RDFFormat;
import org.apache.jena.vocabulary.OWL;
import org.apache.jena.vocabulary.RDF;
import org.apache.jena.vocabulary.RDFS;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

/**
 * Generic XSD → RDF/OWL vocabulary generator — the legislative-kg §11
 * "source-translate any XSD into an emitter (XSD → RDF being the first
 * instance)" capability, and a building block of the future {@code rules_xsd}.
 *
 * <p>Reads a schema as plain XML (no schema resolution — just its declarations)
 * and emits a faithful, *syntactic* ontology in Turtle via the Jena model API:
 *
 * <ul>
 *   <li>named {@code complexType} / {@code simpleType} → {@code owl:Class}
 *   <li>top-level {@code element} → {@code owl:Class} (with {@code rdfs:subClassOf}
 *       its {@code @type} / {@code @substitutionGroup})
 *   <li>{@code attribute} (anywhere, by {@code @name}) → {@code owl:DatatypeProperty}
 *       (range from a built-in {@code xsd:} {@code @type})
 *   <li>{@code xsd:documentation} → {@code rdfs:comment}
 * </ul>
 *
 * <p>The output feeds {@code jena_schemagen} just like a hand-authored vocabulary,
 * so the typed Java views are derived all the way from the publisher's XSD.
 * Content-model object properties (containment) are a documented follow-on; v1
 * covers the class + attribute surface, which is what the curated {@code legal_ir}
 * vocabulary aligns to. Carries zero domain knowledge.
 *
 * <p>Args: {@code --root=<schema.xsd> --namespace=<ns#> --out=<vocab.ttl>}.
 * {@code --namespace} is optional; it defaults to the schema's
 * {@code targetNamespace} with a {@code #} separator.
 */
public final class XsdToVocab {

  private static final String XSD_NS = "http://www.w3.org/2001/XMLSchema";

  public static void main(String[] args) throws Exception {
    String root = null;
    String namespace = null;
    String out = null;
    for (String a : args) {
      if (a.startsWith("--root=")) {
        root = a.substring("--root=".length());
      } else if (a.startsWith("--namespace=")) {
        namespace = a.substring("--namespace=".length());
      } else if (a.startsWith("--out=")) {
        out = a.substring("--out=".length());
      } else {
        System.err.println("xsd_to_vocab: unknown arg: " + a);
        System.exit(2);
      }
    }
    if (root == null || out == null) {
      System.err.println("usage: XsdToVocab --root=<xsd> --out=<ttl> [--namespace=<ns#>]");
      System.exit(2);
    }

    DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
    dbf.setNamespaceAware(true);
    dbf.setValidating(false);
    dbf.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false);
    DocumentBuilder db = dbf.newDocumentBuilder();
    Element schema = db.parse(Paths.get(root).toFile()).getDocumentElement();

    String tns = schema.getAttribute("targetNamespace");
    String ns = namespace != null && !namespace.isEmpty()
        ? namespace
        : (tns.endsWith("#") || tns.endsWith("/") ? tns : tns + "#");

    Model m = ModelFactory.createDefaultModel();
    m.setNsPrefix("", ns);
    m.setNsPrefix("owl", OWL.NS);
    m.setNsPrefix("rdfs", RDFS.uri);
    m.setNsPrefix("xsd", XSD_NS + "#");

    // Ontology header — provenance back to the source schema namespace.
    if (!tns.isEmpty()) {
      m.createResource(ns).addProperty(RDF.type, OWL.Ontology);
    }

    Set<String> attrsSeen = new LinkedHashSet<>();

    // Top-level named types + elements → classes.
    for (Element def : directChildren(schema)) {
      String local = def.getLocalName();
      String name = def.getAttribute("name");
      if (name.isEmpty()) {
        continue;
      }
      if (local.equals("complexType") || local.equals("simpleType") || local.equals("element")) {
        Resource cls = m.createResource(ns + name)
            .addProperty(RDF.type, OWL.Class)
            .addProperty(RDFS.label, name);
        String doc = documentation(def);
        if (doc != null) {
          cls.addProperty(RDFS.comment, doc);
        }
        if (local.equals("element")) {
          String sub = localName(def.getAttribute("substitutionGroup"));
          String type = localName(def.getAttribute("type"));
          if (!sub.isEmpty()) {
            cls.addProperty(RDFS.subClassOf, m.createResource(ns + sub));
          } else if (!type.isEmpty() && !isBuiltin(def.getAttribute("type"))) {
            cls.addProperty(RDFS.subClassOf, m.createResource(ns + type));
          }
        }
      }
    }

    // Every named attribute (anywhere) → a datatype property.
    NodeList attrs = schema.getElementsByTagNameNS(XSD_NS, "attribute");
    for (int i = 0; i < attrs.getLength(); i++) {
      Element attr = (Element) attrs.item(i);
      String name = attr.getAttribute("name");
      if (name.isEmpty() || !attrsSeen.add(name)) {
        continue;
      }
      Resource prop = m.createResource(ns + name)
          .addProperty(RDF.type, OWL.DatatypeProperty)
          .addProperty(RDFS.label, name);
      String doc = documentation(attr);
      if (doc != null) {
        prop.addProperty(RDFS.comment, doc);
      }
      String type = attr.getAttribute("type");
      if (isBuiltin(type)) {
        prop.addProperty(RDFS.range, m.createResource(XSD_NS + "#" + localName(type)));
      }
    }

    Files.createDirectories(Paths.get(out).toAbsolutePath().getParent());
    try (OutputStream os = Files.newOutputStream(Paths.get(out))) {
      RDFDataMgr.write(os, m, RDFFormat.TURTLE_PRETTY);
    }
    System.out.println("xsd_to_vocab: wrote " + m.size() + " triples to " + out);
  }

  private static Iterable<Element> directChildren(Element parent) {
    Set<Element> kids = new LinkedHashSet<>();
    NodeList nl = parent.getChildNodes();
    for (int i = 0; i < nl.getLength(); i++) {
      Node n = nl.item(i);
      if (n.getNodeType() == Node.ELEMENT_NODE && XSD_NS.equals(n.getNamespaceURI())) {
        kids.add((Element) n);
      }
    }
    return kids;
  }

  /** First {@code annotation/documentation} text directly under a definition. */
  private static String documentation(Element def) {
    for (Element child : directChildren(def)) {
      if ("annotation".equals(child.getLocalName())) {
        for (Element gc : directChildren(child)) {
          if ("documentation".equals(gc.getLocalName())) {
            String t = gc.getTextContent();
            return t == null ? null : t.trim().replaceAll("\\s+", " ");
          }
        }
      }
    }
    return null;
  }

  /** Local part of a possibly-prefixed QName ("uslm:LevelType" -> "LevelType"). */
  private static String localName(String qname) {
    if (qname == null) {
      return "";
    }
    int c = qname.indexOf(':');
    return c >= 0 ? qname.substring(c + 1) : qname;
  }

  /** A built-in XML Schema datatype reference (prefix bound to the XSD namespace). */
  private static boolean isBuiltin(String type) {
    return type != null && (type.startsWith("xsd:") || type.startsWith("xs:"));
  }

  private XsdToVocab() {}
}
